# Shell, PATH and installers

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Homebrew prefix
`BREW_PREFIX` is set at shell startup based on `uname -m`:
- Apple Silicon → `/opt/homebrew`
- Intel → `/usr/local`

Always use `$BREW_PREFIX` for any Homebrew path. Never hardcode either prefix.
Never use `$HOMEBREW_BREW_FILE` — it's unreliable across Homebrew versions. Use `brew` directly.

## Machine-specific overrides

**Shell:** `~/env.sh` is sourced at the very end of `zshrc` (silently, `2>/dev/null`).
Use it on any machine for local-only exports, aliases, or PATH additions that should not be committed.

**Git identity:** `~/.gitconfig.local` is included at the end of `git/gitconfig`, after the
platform overlay (`~/.config/git/gitconfig.platform`, Linux only), so local settings win.
The personal email (`villavicencio.david@gmail.com`) is the default. On a work machine,
override with the corporate email in the local file:

```ini
# ~/.gitconfig.local
[user]
    email = <your-work-email>
```

**SSH hosts:** `~/.ssh/config` is not tracked. Per-machine host aliases (e.g. `Host hal` for the Mac mini server, `Host work` for the work Mac) are added directly there. Aliases are required for IDEs that read `~/.ssh/config` to populate Remote-SSH host pickers (Antigravity, VS Code, Cursor) — `ssh hal` working from the shell is not sufficient on its own.

## Paths
- Never hardcode `/Users/<username>/` — always use `$HOME`.
- Never hardcode `/opt/homebrew/` or `/usr/local/` — always use `$BREW_PREFIX`.
- `excludesfile` and `attributesfile` in gitconfig point to `~/.config/git/` (XDG standard, symlinked by Dotbot). Do not change them back to repo-relative paths.
- Google Cloud SDK is installed at `~/.google-cloud-sdk/` (not the default location).
- **`date`, `ls` and the other coreutils are the GNU versions** in every shell that reads
  `zshenv`, agent shells included: it puts `$BREW_PREFIX/opt/coreutils/libexec/gnubin` first on
  PATH. BSD-only flags fail there: `date -j -f …` prints `invalid option -- 'j'` and returns
  nothing. Use the GNU form (`date -u -d '2026-10-21T03:31:00Z' +%s`), or call `/bin/date` for
  BSD behavior. Seen 2026-10-21: a scheduled job computed an empty target time from `date -j`,
  skipped its wait, and fired an hour early.
- **`sed` is not coreutils, so it stays BSD** (`/usr/bin/sed`). GNU sed comes from the separate
  `gnu-sed` formula, and only as `gsed`; its `gnubin` isn't on PATH. A GNU-style
  `sed -i 's/a/b/' file` fails under BSD sed, which reads the script as the backup suffix:
  `undefined label …`. Use `sed -i '' …` or `gsed -i …`. Seen 2026-10-22.

## Post-installer audit
After running any third-party installer that modifies shell config (gcloud, rustup, etc.),
always run `git diff` and fix hardcoded paths before committing. Common offenders:
- Hardcoded `/Users/<username>/` instead of `$HOME`
- Paths in unstable locations (`~/Downloads/`, `/tmp/`)
- POSIX `. ` sourcing instead of zsh `source` or `[[ -f ... ]] &&` guard pattern

An installer that "adds itself to your `.zshrc`" writes into this repo: `~/.config/zsh/.zshrc`
is a link to `zsh/zshrc`. On a machine you don't commit from (e.g. hal), that shows up later
as `M zsh/zshrc` and blocks `git pull`. A machine-specific line goes in `~/env.sh` (sourced
last, untracked); only then discard it from `zsh/zshrc`. Seen 2026-10-09 on hal as the `hal`
account: iTerm2's shell-integration installer appended
`test -e /Users/<account>/.config/zsh/.iterm2_shell_integration.zsh && source …`, with the
literal home path.

## Node version
`NODE_VERSION` is defined in `zsh/zshenv` and used by `helpers/install_node.sh`.
Update it there whenever upgrading Node.

## Lazy loader pattern
All lazy loaders (FZF, pyenv, NVM, RVM) follow the same `_load_X` helper pattern.
**Why:** Direct sourcing of NVM alone adds 200-400ms to shell startup. This pattern
was benchmarked and is critical for keeping `zsh -i -c exit` under 300ms.

```zsh
if [[ <existence-check> ]]; then
  _load_toolname() {
    unset -f _load_toolname cmd1 cmd2
    <initialization>
  }
  cmd1() { _load_toolname; cmd1 "$@"; }
  cmd2() { _load_toolname; cmd2 "$@"; }
fi
```

When adding a new lazy loader, copy an existing one as a template. Never duplicate init
logic across multiple wrapper functions. Use `command <tool>` (not bare `<tool>`) after
`_load_*` to prevent infinite recursion when the shim name matches the binary name.

## uv — native installer, deliberately not the Brewfile
`helpers/install_uv.sh` installs uv from Astral's own installer to `~/.local/bin/uv`
(and `uvx`), skipping if already present. Same reasoning as `install_claude_code.sh`:
`zshenv` puts `~/.local/bin` **ahead of** Homebrew, so a `brew install uv` would sit at a
lower-precedence path and never be the copy that runs — two uvs, the tracked one permanently
shadowed. uv also self-updates (`uv self update`), so a Homebrew copy would drift behind.

**`UV_NO_MODIFY_PATH=1` is required, not cosmetic.** Left unset, the installer appends PATH
lines to `.zshrc` **and** `.zshenv` — both Dotbot symlinks into this repo — so an unguarded
run edits tracked files and dirties the working tree. That is the "Post-installer audit"
hazard, avoidable in advance rather than cleaned up after. `zshenv` already puts
`~/.local/bin` on PATH, so there is nothing for the installer to add. The helper also pins
`UV_INSTALL_DIR` so the destination never depends on the installer's own defaults.

**No Homebrew `python@3.x` is needed for uv's benefit.** uv prefers the interpreters it
manages under `~/.local/share/uv/python/` and provisions one on demand (`uv python install`),
so nothing has to be installed ahead of it. The Hermes runtime's venv is backed by a
uv-managed CPython rather than a system or Homebrew one.

uv *will* discover and use a suitable system interpreter when no managed one satisfies the
request — `uv python list` on this Mac shows the Homebrew 3.12/3.14 builds as usable
candidates — so a brewed Python is redundant here, not unusable. `--managed-python` /
`UV_MANAGED_PYTHON=1` forces the managed path when a project needs that guarantee;
`--no-managed-python` does the opposite.

## NVM lazy loader shims — globals do NOT need one
NVM is lazy-loaded for startup speed. **A globally-installed npm CLI does not need a shim.**
The block prepends the highest installed node version's `bin` dir to `PATH` at shell startup, and these
CLIs are `#!/usr/bin/env node` shebangs that resolve through that same prepend — so they work
in a fresh shell with nvm still unloaded. Verified 2026-08-25: in `zsh -i`, `obscura` resolves
to its real path while `_load_nvm` is still defined (i.e. nvm was never sourced).

An earlier version of this section claimed the opposite, and that error outlived the fact:
the PATH prepend landed 2026-03-11 (`83968b9`), but `bb`/`browse` shims were still added
2026-05-07 (`5ed5c28`) and bought nothing except a needless 200–400 ms `nvm.sh` source on
first call. Both were removed 2026-08-25 along with their retired Browserbase packages.

Current shims: `nvm`, `node`, `npm`, `npx` — nvm's own management commands, which genuinely
need `nvm.sh` sourced. **The one case that does need a shim** is a global installed under a
version other than the highest installed one, which the prepend does not cover.

**The prepend picks the highest installed version, not nvm's `alias/default`** (`sort -V |
tail -1`). Both resolve to v24.13.0 on this Mac, but seven versions are installed and nothing
keeps them aligned: point the alias at an older version and PATH still carries the highest,
while `_load_nvm` — once anything triggers it — sources `nvm.sh`, applies the alias, and
switches `node` mid-shell. Worth knowing before trusting either as "the" node version.

Note: `claude` does not need an NVM shim — it is not an npm global. `helpers/install_claude_code.sh`
installs it via Anthropic's native installer (`curl -fsSL https://claude.ai/install.sh | bash`)
to `~/.local/bin/claude` (which `zshenv` puts ahead of Homebrew on `PATH`). The Brewfile does
not manage it; the Homebrew cask lags, so the native installer + Claude Code's auto-updater is
preferred.

That auto-updater ignores `"autoUpdates": false` in `~/.claude.json`, a legacy key; this Mac
also carries `"autoUpdatesProtectedForNative": true` next to it. It checks at startup and
periodically while a session runs. On 2026-10-09, 2.1.295 landed with no shell activity, from a
long-running session, and 2.1.296 landed 15 s after a `claude --continue` launch. Topgrade
wasn't involved. `~/.claude/daemon.log` only records the daemon noticing the new binary
("self-restarting for upgrade"). The documented off switch is `env.DISABLE_AUTOUPDATER = "1"`
in `settings.json` (`DISABLE_UPDATES` also blocks `claude update`), and `claude doctor`
shows which setting is in effect (code.claude.com/docs/en/setup, read 2026-10-10).

**`zshenv`'s order only holds because `zshrc` re-applies it.** Two things run between them and
undo it: `brew shellenv` (Homebrew 7 prepends `/opt/homebrew/bin` with a plain `export PATH=`;
the old `grep -v path_helper` filter caught nothing once that changed) and, in login shells, the
`path_helper` in macOS's `/etc/zprofile`. So `zshrc` re-sources `zshenv` right after `brew
shellenv`; `zsh/zprofile.server` does the same on hal (shellenv first, then the re-source), so
the order holds in hal's non-interactive login shells too. Don't remove either line to save a fork.
When it broke (found 2026-10-08), a hand-installed `claude-code@latest` cask won every nested shell
(tmux, the agent's Bash), so `claude update` reported "managed by Homebrew" while the
native install sat behind it. On desk Macs, `dot doctor` now fails when `claude` doesn't resolve
to `~/.local/bin/claude` or that native install is missing. Not covered: desk non-interactive
login shells (`zsh -l -c`) never read `zshrc`, so they keep
`path_helper`'s order (VIL-315). Write-up:
`docs/solutions/runtime-errors/brew-shellenv-path-prepend-shadows-native-claude-2026-10-08.md`.

## OMZ plugin sync
When adding an Oh My Zsh plugin to the `plugins=()` list in `zshrc`, also add the corresponding
`git clone` to `helpers/install_omz.sh` so it gets installed on fresh machines.
