# Dotfiles

This repo is the single source of truth for two Macs:

| Machine | OS | Hardware | Role |
|---|---|---|---|
| personal | macOS Tahoe | M-series | Primary, source of truth |
| work | macOS Sequoia | M-series | corporate-managed |

Managed by [Dotbot](https://github.com/anishathalye/dotbot). Run `./install` to set up a machine — the wrapper runs a shared `dotbot-conf/base.yaml` and then the platform layer (`dotbot-conf/darwin.yaml` on Darwin, `dotbot-conf/linux.yaml` on Linux) automatically (no active Linux target as of 2026-05-21 — the Hetzner VPS was re-purposed away from a dotfiles tree; see retire-noted runbook in `docs/solutions/cross-machine/vps-dotfiles-target.md` if you ever want to revive a Linux target).

> **Tool-neutral brief:** [`AGENTS.md`](AGENTS.md) is the canonical, tool-agnostic
> description of the repo's layout, conventions, common tasks, and verification commands —
> the version any agent (Codex, Cursor, …) should read. This file keeps the same
> conventions **plus** Claude Code-specific behavior and the full gotcha write-ups, so it
> stays self-sufficient for Claude Code loading. If the two ever drift, reconcile them.

---

## Structure

```
brew/           Brewfile for all Homebrew packages and casks
btop/           btop system monitor config
docs/           Compound-engineering pipeline artifacts:
                - docs/brainstorms/  Requirements docs from /ce-brainstorm
                - docs/ideation/     Idea-survival outputs from /ce-ideate
                - docs/plans/        Implementation plans from /ce-plan
                - docs/solutions/    documented solutions to past problems (bugs, best practices, workflow patterns), organized by category with YAML frontmatter (module, tags, problem_type)
ci/             CI assets (Dockerfile for install-matrix workflow)
git/            gitconfig, gitignore, gitattributes
helpers/        Bash scripts called by the install pipeline
herdr/          Herdr agent-multiplexer config (config.toml symlinked into ~/.config/herdr/)
iterm/          iTerm2 preferences (exported plist, includes Shift+Enter key mapping)
lazygit/        lazygit config
npm/            npm global package list (npm-requirements.txt)
nvim/           Neovim config (custom/ is symlinked into ~/.config/nvim/)
otty/           Otty terminal config + the iTerm2-imported theme. COPY-SEEDED by
                helpers/install_otty.sh, never symlinked (see conventions below)
starship/       Starship prompt config (command_timeout is a global top-level key)
bin/            Repo CLI — bin/dot (symlinked to ~/.local/bin/dot)
  lib/*.py      Python helpers for doctor/bench. Real files, NOT heredocs — see
                "No heredocs in bin/dot" below
tmux/           tmux config
topgrade/       Topgrade system updater config
vale/           Vale prose linter config
zsh/
  zshenv        Environment variables, PATH, BREW_PREFIX — sourced early
  zshrc         Shell config, plugins, lazy loaders
  alias.sh      Aliases
  functions.sh  Functions (also sources zsh/functions/*.sh)
  functions/    Individual function files (man_colorful, mkdir_and_cd, etc.)
claude/
  CLAUDE.md              Global Claude Code instructions (symlinked to ~/.claude/CLAUDE.md)
  settings.json          Claude Code settings — plugins, allowed tools (symlinked to ~/.claude/settings.json)
  statusline-command.sh  Statusline script (symlinked to ~/.claude/statusline-command.sh)
  hooks/                 Claude Code hooks (e.g. tmux-attention.sh)
```

Note: the `/handoff`, `/pickup`, and `/review-claudemd` slash commands now live in an
external Claude Code plugin, not this repo. The only repo-local command is
`.claude/commands/ticket.md` (a hidden `.claude/` dir for working *in* this repo).

---

## Key conventions

### Homebrew prefix
`BREW_PREFIX` is set at shell startup based on `uname -m`:
- Apple Silicon → `/opt/homebrew`
- Intel → `/usr/local`

Always use `$BREW_PREFIX` for any Homebrew path. Never hardcode either prefix.
Never use `$HOMEBREW_BREW_FILE` — it's unreliable across Homebrew versions. Use `brew` directly.

### Machine-specific overrides

**Shell:** `~/env.sh` is sourced at the very end of `zshrc` (silently, `2>/dev/null`).
Use it on any machine for local-only exports, aliases, or PATH additions that should not be committed.

**Git identity:** `~/.gitconfig.local` is included at the end of `git/gitconfig`.
The personal email (`villavicencio.david@gmail.com`) is the default. On a work machine,
override with the corporate email in the local file:

```ini
# ~/.gitconfig.local
[user]
    email = <your-work-email>
```

**SSH hosts:** `~/.ssh/config` is not tracked. Per-machine host aliases (e.g. `Host openclaw-prod` for the VPS, `Host work` for the work Mac) are added directly there. Aliases are required for IDEs that read `~/.ssh/config` to populate Remote-SSH host pickers (Antigravity, VS Code, Cursor) — `ssh root@openclaw-prod` working from the shell is not sufficient on its own.

### Paths
- Never hardcode `/Users/<username>/` — always use `$HOME`.
- Never hardcode `/opt/homebrew/` or `/usr/local/` — always use `$BREW_PREFIX`.
- `excludesfile` and `attributesfile` in gitconfig point to `~/.config/git/` (XDG standard, symlinked by Dotbot). Do not change them back to repo-relative paths.
- Google Cloud SDK is installed at `~/.google-cloud-sdk/` (not the default location).

### Post-installer audit
After running any third-party installer that modifies shell config (gcloud, rustup, etc.),
always run `git diff` and fix hardcoded paths before committing. Common offenders:
- Hardcoded `/Users/<username>/` instead of `$HOME`
- Paths in unstable locations (`~/Downloads/`, `/tmp/`)
- POSIX `. ` sourcing instead of zsh `source` or `[[ -f ... ]] &&` guard pattern

### Secret hygiene
Every commit is scanned by gitleaks via a `pre-commit` hook. Config lives in
`.pre-commit-config.yaml` at repo root, the hook is wired by `helpers/install_pre_commit.sh`,
and `./install` runs that helper automatically on both macOS and Linux.

The hook entry is `gitleaks git --pre-commit --redact --staged --verbose` — only
**staged diffs** are scanned, not the full working tree or history. The historical
`bash/.exports` leak (fingerprinted in
`docs/solutions/security/2018-leaked-github-pats-and-trufflehog-verified-false-trap-2026-05-06.md`)
is invisible to the hook by design — manual audits + the postmortem's grep recipe handle history.

**Entropy gate.** Gitleaks's `github-pat` rule (and most provider rules) include an
entropy threshold to avoid false positives on test fixtures. A token like
`ghp_aaaaaaaa...` (entropy 0) is *not* flagged by design. To smoke-test the hook,
use a high-entropy fake like `ghp_xKy7mFP2zL9QrT4vN8bH3sD1jE6cWa0pIuYg`. <!-- gitleaks:allow -->

**False positives.** Add an inline `# gitleaks:allow` comment on the offending line,
or extend the repo with a `.gitleaks.toml` allowlist entry. Default ruleset is broad —
some collisions on UUIDs / hex SHAs / fixture data are expected over time.

**Intentional bypass.** `git commit --no-verify`. Reflog records the bypass but not the
*why*; document the reason in the commit message body when bypassing on purpose, so the
audit trail distinguishes "I knew" from "I forgot the hook exists."

**Upstream gotcha — `pass_filenames: false` override is required.** Gitleaks's published
`.pre-commit-hooks.yaml` for the `gitleaks-system` variant omits `pass_filenames: false`
(the `gitleaks` and `gitleaks-docker` variants set it correctly). Without our local
override in `.pre-commit-config.yaml`, pre-commit appends each staged filename as a
positional arg, gitleaks fails with `cannot change to '<file>': Not a directory`, and
the hook silently reports "no leaks found" on every commit — verified against
gitleaks v8.30.1. If gitleaks's hook config ever fixes this upstream, the override
becomes a harmless no-op.

**Version pin.** Gitleaks version is pinned in two places that must match: the `rev:` in
`.pre-commit-config.yaml` and `GITLEAKS_VERSION` in `helpers/install_pre_commit.sh`
(used for the Linux binary download). Bump both together.

### Node version
`NODE_VERSION` is defined in `zsh/zshenv` and used by `helpers/install_node.sh`.
Update it there whenever upgrading Node.

### Lazy loader pattern
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

### uv — native installer, deliberately not the Brewfile
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

### NVM lazy loader shims — globals do NOT need one
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

### tmux-window-namer skill (external plugin + repo-side tmux infra)
The **tmux-window-namer skill itself now lives in an external Claude Code plugin**
(the `dv` plugin), not this repo. What this repo keeps is the **tmux-side
infrastructure** the skill drives: the skill stores per-window state in two tmux
user options (`@win_glyph`, `@win_glyph_color`) read by the ternary in
`tmux/tmux.display.conf`'s `window-status-format`. Title text always uses default
tmux colors so inactive tabs naturally dim — only the glyph carries palette color.
Persistence is a JSON sidecar at `~/.config/tmux/window-meta.json`, written by
`tmux/scripts/save-window-meta.sh` and re-applied on every client attach via
`tmux/scripts/restore-window-meta.sh` (wired up in `tmux/tmux.general.conf`
with `set-hook -g client-attached`). The curated palette the skill draws from is
part of the plugin, not this repo.

### Claude Code tmux tab indicator
`claude/hooks/tmux-attention.sh` is invoked by Claude Code hooks (declared in
`claude/settings.json`) to drive a per-window tmux user option `@claude_status`,
which is read by a ternary in `tmux/tmux.display.conf`'s `window-status-format`.
Active states: `asking` (bright yellow `\uf128` for any `PermissionRequest` —
Bash tool-use confirmations, AskUserQuestion, all user-decision prompts render
the same glyph), spinner frame (orange star cycling at 150ms), or unset (no
icon). An amber `waiting` branch exists in the tmux ternary as reserved state
for future non-permission attention events but is not currently written by
the hook. The spinner runs as a disowned bash subshell tagged
`claude-spinner-marker-<pane>` so `pkill` can find leaks. It self-terminates
when (a) the sentinel file is removed, (b) Claude Code's PID is gone, or
(c) the 5-minute safety cap is hit. Its cleanup block is gated on
sentinel-still-exists so it does not race the main-thread state writer — see
`docs/solutions/runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md`.
If a leaked loop ever shows up, kill it via `pkill -f claude-spinner-marker`.

### OMZ plugin sync
When adding an Oh My Zsh plugin to the `plugins=()` list in `zshrc`, also add the corresponding
`git clone` to `helpers/install_omz.sh` so it gets installed on fresh machines.

### Otty config — copy-seeded, never symlinked
`otty/config.toml` and `otty/themes/com-googlecode-iterm2.ottytheme` are the **only
tracked configs delivered by copy instead of a Dotbot `link:`**. `helpers/install_otty.sh`
(wired into `dotbot-conf/darwin.yaml` as a shell step) copies them into `~/.config/otty/`
**only when absent**, so a live config is never clobbered.

**Do not "fix" this by adding a `link:` entry.** `otty config set` and the Settings UI
write via temp-file + `rename(2)`, which replaces the path outright — a symlink there is
destroyed on the first settings change, and the repo copy becomes a silently-orphaned
stale twin. The CLI still exits 0 and prints the value it "set," and `git status` stays
clean, so nothing surfaces until a fresh install overwrites months of settings. Verified
against otty 1.3.1; full reproduction in
`docs/solutions/integration-issues/otty-config-symlink-hostile-atomic-rename-2026-08-07.md`.

Because a copy can drift, `dot drift` reports Otty alongside Brewfile/npm. It compares
**normalized** forms (`otty config show`) on both sides — the raw live file accumulates a
long tail of `# key = value (reset to default)` comments that would swamp a plain diff.
`otty config show` is verified lossless and read-only. To record live changes:

```bash
dot drift                                 # see what diverged
bash helpers/install_otty.sh --capture    # regenerate otty/config.toml, then commit
```

`--capture` regenerates rather than `cp`s: the tracked file is the normalized form plus a
comment header, and a raw copy would destroy both.

Tracking boundary: **only** `config.toml` + the iTerm2-imported theme. The other 24
`themes/*.ottytheme` are app-seeded reference themes Otty regenerates on first run;
`fonts/` holds only an app-generated README and `recipes/` is empty. Do not widen the
boundary to the whole directory.

`otty config set --transient` is advertised in `--help` but errors out
(`Transient config not yet implemented`) — every config experiment persists, so back up
`~/.config/otty/config.toml` first.

### A hook symlinked into the repo is branch-fragile — land the file before wiring it
`~/.claude/hooks/*.sh` are Dotbot symlinks **into this working tree**, so they resolve against
whatever branch is checked out. A hook whose file exists only on a *feature* branch goes
dangling the moment you switch away, and Claude Code then prints a non-blocking error on
**every** `SessionStart` and `UserPromptSubmit`, in every session, across every project:

```text
SessionStart:startup hook error
Failed with non-blocking status code: /bin/sh: ~/.claude/hooks/<hook>.sh: No such file or directory
```

Observed 2026-08-25 with `herdr-blank-state.sh`: registered in `settings.json` and symlinked
while on its feature branch, then broken by a routine `git checkout` of an unrelated branch.
`tmux-attention.sh` never hit this only because it has been on `master` for months.

**So: do not register a hook in `settings.json` until its file is on `master`.** If you need it
live before the PR merges, install a *copy* rather than a symlink — a copy is branch-independent:

```bash
tmp="$(mktemp)"
git show <branch>:claude/hooks/<hook>.sh > "$tmp" && chmod +x "$tmp" &&
  mv -f "$tmp" ~/.claude/hooks/<hook>.sh
```

Write to a temp file and `mv` over the destination — **do not redirect straight at the hook
path.** When that path is still the dangling symlink, `>` follows the link and creates its
*target*: verified 2026-08-25, the redirect **succeeds silently**, the symlink stays a
symlink, and the content lands at the target path inside the repo working tree. So the hook
still does not exist where Claude Code looks for it, and you have also dropped an untracked
file into the repo. `mv -f` replaces the link itself, atomically.

Re-run `./install` after the merge to restore the tracked symlink, which is safe once the file
is on the default branch and therefore present on every branch cut from it.

### Claude Code `settings.json` — copy-seeded, never symlinked
`claude/settings.json` is the **second** tracked config delivered by copy rather than a
Dotbot `link:` (Otty is the first, above). `helpers/install_claude_settings.sh` seeds
`~/.claude/settings.json` **only when absent**, so a live config is never clobbered.

**Do not "fix" this by restoring a `link:` entry.** The file has three independent writers
besides this repo — Claude Code itself (`effortLevel`, `tui`, notification prefs, `autoMode`),
`herdr integration install`, and Otty's agent-integration installer — each rewriting it in
place. A symlink there survives until the first write, after which the live file is a regular
file and the repo copy is a silently-orphaned stale twin.

That already happened. The link was replaced at some point before 2026-08-25 and the repo copy
went stale from **2026-08-07** — its last commit — while the live file drifted for eighteen days.
Nothing surfaced it: `git status` stayed clean, because from git's side nothing had changed.

**The damage was not cosmetic.** In that window the live file regrew a legacy top-level
`allowedTools` key holding 18 rules while `permissions.allow` fell to 1 — silently re-arming the
precedence trap PR #127 removed (see "one allowlist, not two" below). It also accumulated an
`autoMode.environment` block naming a *different project's* trusted repo and services, in the
cross-machine user-scope file whose own `"//"` header forbids machine- or project-specific values.

Because a copy can drift, `dot drift` reports Claude settings alongside Brewfile/npm/Otty, and
**warns loudly if `allowedTools` ever reappears**. It compares **capture-normalized** forms —
the live file legitimately carries machine-local keys that are deliberately untracked, so a raw
diff would report permanent un-actionable drift. To record live changes:

```bash
dot drift                                            # see what diverged
bash helpers/install_claude_settings.sh --capture    # regenerate claude/settings.json, then commit
```

`--capture` regenerates rather than `cp`s: it drops the machine-local keys
(`effortLevel`, `autoMode`, `mcpServers`, and `allowedTools` — which must never be tracked),
re-prepends the tracked `"//"` header, and rewrites absolute `$HOME` paths back to `~/`
(installers write literal `/Users/<you>/...`; Claude Code expands `~` in hook commands).

**Agents cannot write this file** — the auto-mode classifier blocks it by design, so it stops an
agent widening its own permissions. `helpers/migrate_claude_settings.py` exists for a machine
whose settings predate this scheme (folds `allowedTools` back, registers the blank-state hook);
it is idempotent, backs up first, and **you run it yourself**, not an agent.

### Herdr — agent multiplexer (config symlinked; writes flow back)
`herdr` (Brewfile) is a tmux-shaped client/server multiplexer with native agent
awareness: it detects a Claude Code pane via screen manifests, tracks
blocked/working/done/idle state (what `claude/hooks/tmux-attention.sh` hand-rolls
for tmux), and — with the official integration installed — resumes Claude Code
conversations across server restarts via `claude --resume <id>`.

- **Config is symlinked, not copy-seeded.** Unlike Otty, herdr rewrites
  `~/.config/herdr/config.toml` **in place** (verified on 0.8.0: `herdr config
  reset-keys` preserves the inode), so the Dotbot `link:` entry is safe and live
  changes surface as `M herdr/config.toml` — diff and commit them, same as
  `claude/CLAUDE.md`. Link the **file only**, never the directory:
  `~/.config/herdr/` also holds the socket, logs, `session.json`, and
  `config.toml.bak-*` backups.
- **Server lifecycle:** `brew services start herdr` (launchd, keep_alive; log at
  `$BREW_PREFIX/var/log/herdr.log`). Detach with `ctrl+space q` — panes keep
  running. `herdr server stop` (and any server restart, including
  `brew services restart` after an upgrade) **kills all pane processes**; layout
  is snapshot-restored and supported agent conversations resume
  (`[session] resume_agents_on_restore`), but plain shells restart fresh.
  Boot-race caveat (reboot, 2026-08-18): if a declarative pane's `command`
  fails at restore (ssh before the network is up), the pane degrades to a
  plain shell AND the command is silently dropped from the layout — later
  restarts restore the shell. Fix: re-run `layout.apply` with the original
  pane node. Filed upstream: herdrdev/herdr#2966.
- **Updates ride `brew upgrade`** (topgrade covers it). `herdr update` and the
  experimental `--handoff` live-update are disabled for Homebrew installs.
- **`herdr integration install <agent>` is a human step** — it writes hooks into
  the agent's own config (for claude: `~/.claude/hooks/herdr-agent-state.sh` +
  `~/.claude/settings.json`, which the auto-mode classifier blocks agents from
  editing). Installed: claude and codex, both v7; codex's hook lives in
  `~/.codex/` and was merged alongside the pre-existing Otty hooks in
  `hooks.json`. Check `herdr integration status` after major agent-CLI updates.
- **Prefix is `ctrl+space`, deliberately matching tmux** — one muscle-memory
  "multiplexer key" across both apps, which are not nested in normal use. If you
  do nest, tmux's `send-prefix` binding passes it through on a double-tap. Herdr
  can host tmux in a pane or run inside tmux, but agent detection does not see
  through a nested tmux.
- **Remote agent surfaces (`atlas ⚓` / `axiom ∴` / `atlas-tools ⚙`):** each workspace hosts a VPS
  TUI through an ssh shim whose *name* matches a detection-manifest alias —
  herdr identifies these ssh panes by process name. **The name trick is for ssh
  panes only** — a *local* TUI needs none of it: claude and hermes panes are
  detected natively regardless of process name (`vice ♠`'s `hermes chat` runs as
  venv python and detects as `hermes`; verified 2026-08-25) — the documented
  `HERDR_AGENT` env hint applies to sandbox-wrapper foregrounds (`fence`/`nono`)
  and does NOT fire for ssh foregrounds on 0.8.0 (re-verified 2026-08-18:
  ssh + env hint → pane undetected; herdrdev/herdr#2961 has the repro). Do not
  re-derive the "HERDR_AGENT env pin is dead" finding from the 2026-08-18
  morning session — it was a measurement artifact: `layout.apply`'s `env` IS
  delivered to pane processes (verified by in-pane `printenv`); `ps eww`
  cannot read other processes' env on modern macOS and shows nothing, which
  faked the "var absent" result. Full write-up:
  `docs/solutions/best-practices/verify-the-instrument-before-trusting-a-negative.md`. `~/.local/bin/hermes-agent`
  attaches the Hermes TUI (Atlas, detected as hermes);
  `~/.local/bin/claude-code` attaches AXIOM's Claude Code
  (detected as claude, renamed `axiom`) via
  `sudo -u node tmux -L axiom attach -t AXIOM` — since the 2026-07-14 vault
  fold AXIOM runs as **node** on the dedicated socket `-L axiom`. **Since
  2026-08-19 each shim is a repo-tracked auto-reconnect wrapper**
  (`herdr/shims/`, symlinked into `~/.local/bin`): it loops ssh via a raw
  alias in `~/.local/libexec/<same-name>` (which preserves the detected
  process name), retrying every 10s on any nonzero exit and closing only on
  a clean detach (exit 0). Panes therefore survive sleep/network loss — the
  single-pane workspaces no longer vanish overnight, agent renames persist,
  and the #2966 restore boot-race self-heals. Client keepalives back it up:
  `~/.ssh/config` `Host openclaw-prod` carries `ServerAliveInterval 60` +
  `ServerAliveCountMax 120` (machine-local, untracked). Both shims
  are Dotbot-managed (`helpers/install_herdr_agents.sh`, darwin.yaml).
  > ⚠ **A Hermes install on this Mac clobbers `~/.local/bin/hermes-agent`.**
  > Upstream's `install.sh` writes three entrypoints (`hermes`, `hermes-acp`,
  > `hermes-agent`) and the third overwrites the Dotbot symlink to
  > `herdr/shims/hermes-agent` — Atlas's auto-reconnect wrapper, whose *name*
  > is what herdr's hermes detection manifest matches. The break is **latent**:
  > a running pane keeps its already-exec'd process and looks healthy until the
  > next restart, then launches a *local* Hermes agent instead of ssh-ing to
  > the VPS. **Re-run `helpers/install_herdr_agents.sh` after any Hermes
  > install or reinstall** (idempotent). Detect with
  > `ls -la ~/.local/bin/hermes-agent` — healthy is a *symlink*; a regular file
  > dated at your last install is the bug. `claude-code` is unaffected
  > (different name), and so is `vice ♠` (its pane runs `hermes chat` →
  > `~/.local/bin/hermes`). Full write-up: `~/Projects/agents/docs/solutions/`
  > `integration-issues/hermes-installer-clobbers-herdr-shim-hermes-agent-Mac-20260825.md`
  > (observed + fixed 2026-08-25).

  Each remote tmux carries `set-titles on` + `set-titles-string "#{pane_title}"` so
  the TUIs' OSC titles drive herdr states through the nested tmux. Never
  restart `hermes-tmux.service` casually — it drops Atlas's in-memory history
  (see ~/Projects/agents docs for Hermes rules).
- **`atlas-tools ⚙` — a remote CLAUDE CODE surface, not a TUI attach** (added
  2026-08-25, `prefix+t`). It reuses the existing `claude-code` ssh alias rather
  than adding a third shim: detection keys on the ssh child's *process name*, and
  two panes may share one alias since the pane command supplies different args.
  `herdr agent rename` is what tells them apart (`axiom` vs `atlas-tools`).

  ```text
  cwd:     $HOME                        # local placeholder — herdr's cwd is ALWAYS local
  command: ~/.local/bin/claude-code root@openclaw-prod -t \
           "sudo -u node tmux -L atlas-tools -f /home/node/.config/tmux/atlas-tools.conf \
            new-session -A -s ATLAS-TOOLS -c /home/node/Projects/atlas-tools"
  ```

  **A remote project needs no Mac-side checkout.** herdr's pane `cwd` is where the
  local ssh process starts and nothing more; the working directory is established
  remotely by the ssh command. The repo lives only at
  `/home/node/Projects/atlas-tools` on openclaw-prod, owned by `node`, and every
  git/uv/test/lint/Claude Code command runs there.

  `new-session -A` makes the pane **self-healing**: it attaches if the session
  exists and creates it otherwise, so a VPS reboot needs no systemd unit — the
  auto-reconnect shim retries, and the first successful attach rebuilds the
  session. This is why `atlas-tools` has no `*-tmux.service` twin.

  **`-f <conf>` is load-bearing.** tmux's `set-titles` default is `off`, and that
  option is what forwards the inner TUI's OSC title outward for herdr to read
  state through a nested tmux. node has no `~/.tmux.conf`, and options set at
  runtime die with the tmux server — so the socket gets its own conf file,
  scoped with `-L`/`-f` so it cannot disturb the `axiom` or `default` sockets.
  > The `axiom` socket ran with `set-titles off` (tmux's default) until
  > 2026-08-25, despite this file claiming every remote tmux carried it on. It
  > now has its own `~/.config/tmux/axiom.conf`, applied at runtime without a
  > server restart.
  >
  > **That was NOT why `axiom ∴` read `agent_status: unknown`** — a first guess
  > that the evidence killed. The pane was running `/bin/zsh -il`, the shim's
  > clean-detach fallback: something detached the ssh, the wrapper exited 0, and
  > the pane sat at a shell. No agent process, so nothing to detect. The remote
  > side was healthy the whole time (`claude --continue` alive, session intact).
  > **A workspace reading `unknown` means look at the pane's foreground process
  > first** (`pane.process_info`) — a fallback `zsh` is the tell. Recovery is
  > `layout.apply` over the existing tab, then `herdr agent rename`, since a
  > recreated pane loses its name.

- **Local agent pane template (fleet standard, revised 2026-08-19):** a local
  Claude Code agent runs as a declarative pane with command
  `["/bin/zsh", "-l", "-c", "claude; exec /bin/zsh -il"]` and its project dir as
  cwd. Two deliberate parts: the **login zsh** (`-l`) rebuilds PATH from `zshenv`
  because the herdr server spawns pane commands with its bare launchd env (so
  both `claude` and its subshells resolve tools); the **`; exec /bin/zsh -il`
  fallback** is the fleet's "a pane never self-closes" rule — when claude exits
  (a stray `/exit`, a crash), the pane drops to an interactive shell instead of
  vanishing and closing its tab. Type `claude` to relaunch. No ssh shim for local
  agents — herdr's claude integration detects them natively and resume-on-restore
  carries the conversation across server restarts. Rename with `herdr agent
  rename`; renames don't survive pane recreation — reapply after a degraded
  restore, along with `layout.apply` if the command was dropped (#2966). The same
  never-self-close rule is baked into the remote shim wrappers (`herdr/shims/`),
  so it holds fleet-wide. **When building any new agent, use this template and
  route the change through the standard flow** (see the global CLAUDE.md
  "Herdr fleet & agent building").
  - **Diagnosing and rebuilding a degraded pane.** `layout.export` is the test:
    a pane node with **no `command`** key is degraded — it came back as a bare
    shell (the #2966 boot-race, or a pane made by hand) and someone started
    `claude` inside it, so it *looks* fine and is detected normally, but the next
    server restart returns an empty shell. `ps` confirms it: a healthy pane's
    claude is a child of `herdr server` or of `/bin/zsh -l -c …`, a degraded
    one's is a child of plain `-zsh`. Rebuild by applying the template to the
    **existing tab** — workspace and tab survive, so the workspace label and jump
    key are untouched — and **omit `pane_id`** so herdr replaces the pane instead
    of re-tagging the running one. NDJSON over the socket; `nc -U` works on macOS
    and returns immediately:

    ```bash
    S=~/.config/herdr/herdr.sock
    echo '{"id":"1","method":"layout.export","params":{"tab_id":"w1:t1"}}' | nc -U $S
    echo '{"id":"1","method":"layout.apply","params":{"tab_id":"w1:t1","focus":true,"root":{"type":"pane","cwd":"'"$HOME"'/Projects/Personal/dotfiles","command":["/bin/zsh","-l","-c","claude; exec /bin/zsh -il"]}}}' | nc -U $S
    ```

    Two API gotchas, both fail-fast: `layout.apply` takes **`tab_id` or
    `workspace_id`, never both** (`invalid_target`) — pass `tab_id` alone when
    rebuilding one pane in place; and every request needs a `params` key, even
    the list calls, which take `{}` (`missing field params`). A third is
    **silent**: `layout.export` *ignores* `workspace_id` and returns the
    **focused** workspace's layout — believable data for the wrong target
    (reproduced 2026-08-25) — so always address it by `tab_id`. `layout.apply`
    kills the pane's live agent session, so do it at a boundary (a `/clear` or
    model switch), not mid-task, and reapply `herdr agent rename` afterward if
    that pane had one.
  - Current local agents on this template (jump keys are `[[keys.command]]`
    entries in `herdr/config.toml`; shift-chords where the plain letter is taken
    by a default binding or an earlier agent):

    | Agent | Dir | Purpose | Jump |
    |---|---|---|---|
    | `melos ♪` | `~/Projects/melos` | Spotify curator | `prefix+m` |
    | `sites ✦` | `~/Projects/sites` | umbrella of symlinks to the personal-website repos (davidandbrittanie.com, davidv.sh serving villavicencio.dev, ibmcconstruction.com); each site stays its own repo + Vercel project | — |
    | `borealis ❆` | `~/Projects/borealis` | native SwiftUI prompt-library app (ex-Forge, migrated 2026-08-20) | `prefix+shift+b` |
    | `argus ◉` | `~/Projects/agents` | Hermes/Atlas ops project (browse-gateway consumer `argus`) | `prefix+shift+a` |
    | `skills ⚒` | `~/Projects/skills` | Claude Code skills workshop | `prefix+shift+s` |
    | `obscura ✇` | `~/Projects/browse-gateway` | the Obscura browse-gateway itself | `prefix+shift+o` |
    | `eidos ❖` | `~/Projects/eidos` | Eagle library curation | `prefix+shift+i` (`e`/`shift+e` are edit_scrollback / remove_worktree) |
    | `orrery ☉` | `~/.forge-projects/tranquil-dune` (aka `~/Projects/orrery`) | Forge-resident jobs dashboard (orrery.ui8.dev) — see "Forge-resident hybrid agents" below | `prefix+y` (`o`/`shift+o` are open_notification_target / obscura; `y` as in orrer**y**) |
    | `vice ♠` | `~/Obsidian/vice` | Vice Gage — native local **Hermes** agent (personal media curation; Obscura + Eagle MCPs). Pane command is the template with `hermes chat` in place of `claude`; herdr's hermes detection manifest identifies the venv process natively, no shim (verified 2026-08-25). Setup brief: `~/Projects/agents/docs/plans/2026-08-25-001-…` | `prefix+shift+v` (plain `v` is split-vertical's default) |

    Rebuilding the `vice ♠` pane after a degraded restore (#2966) follows the
    standard recipe above with this pane node, then `herdr agent rename` (renames
    don't survive pane recreation, and the jump key targets the agent name):

    ```bash
    echo '{"id":"1","method":"layout.apply","params":{"tab_id":"<wN:tN>","focus":true,"root":{"type":"pane","cwd":"'"$HOME"'/Obsidian/vice","command":["/bin/zsh","-l","-c","hermes chat; exec /bin/zsh -il"]}}}' | nc -U ~/.config/herdr/herdr.sock
    /opt/homebrew/bin/herdr agent rename <pane-id> vice
    ```

- **Forge-resident hybrid agents** (SOP, established 2026-08-20 with `orrery ☉`).
  For a project that legitimately *stays* in Forge — UI-heavy, actually using
  Forge's stories canvas / dev server / publishing — but wants plain Claude Code
  in herdr for non-UI lanes, herdr-ize it **in place**:
  - **Pane cwd = the physical `~/.forge-projects/<codename>` path.** Herdr spawns
    pane processes via `chdir`, and the kernel resolves symlinks there, so Claude
    Code's project identity is always the physical path — pointing the pane at a
    symlink buys nothing and hides the mechanism. Otherwise it's the standard
    fleet pane template.
  - **Add a convenience symlink `~/Projects/<name>` → the codename dir.** Pure
    ergonomics: it gives the project its human name (Forge dirs carry codenames
    like `tranquil-dune`) and keeps the one-projects-dir view complete. It does
    not affect harness identity (see above).
  - **One slug, two harnesses — that's the payoff.** Forge's embedded ACP
    sessions and the herdr pane share the same project slug, so they share the
    memory symlink → vault AND the transcript history: `--resume`/`--continue`
    in the herdr pane lists the Forge sessions' conversations. Continuity is
    free; don't "fix" the shared slug.
  - **Standard bootstrap still applies — verify, don't redo.** The Forge
    sessions have usually already done vault + CLAUDE.md Vault declaration +
    memory symlink; the herdr-side additions are just workspace, rename, jump
    key, roster row.
  - **One working tree, one writer at a time.** Don't run the Forge ACP agent
    and the herdr pane on overlapping edits — split lanes (UI in Forge, non-UI
    in the pane) and let HANDOFF/vault memory carry the seam. Interactive-only
    flows (MCP OAuth, `/mcp` auth) can't run in Forge's non-interactive ACP
    sessions — do them in the herdr pane.
  - **Hybrid repos get a remote, and the PR is the seam** (instituted 2026-08-21
    after orrery's git init). Give the project a GitHub remote (private by
    default — collector-style code maps David's infra) and route BOTH harnesses
    through branch → PR, never local merges or shared uncommitted work on the
    default branch. Each lane's work lands as a reviewed unit the other harness
    pulls cleanly; two agents never meet in a dirty tree.
  - **Never move or rename the Forge dir from outside** — Forge manages it.
    Renaming is Forge's job; moving out entirely is a deliberate de-Forge
    migration (borealis, 2026-08-20: mv + new-slug memory symlink + doc/Linear
    repoints — old-slug transcripts stay behind).
- **Phone access is Moshi (SSH/mosh), not a gateway app** (since 2026-08-21;
  replaced Conduit). Moshi (getmoshi.app) connects straight to this Mac —
  `zs-macbook-pro.tail31dc0a.ts.net`:22, user `dvillavicencio`, Key File auth
  (the `moshi`-comment line in `~/.ssh/authorized_keys`), Connection "Auto" →
  Mosh — then `herdr` in the session attaches the whole fleet. Requires
  Tailscale active on the phone; `mosh-server` rides the Brewfile and zshenv's
  PATH. **No server-side infrastructure exists for mobile access** — Conduit's
  pieces (the `conduit_push` Hermes plugin + a tailnet-only `tailscale serve`
  HTTPS proxy to the Hermes gateway on openclaw-prod) were torn down
  2026-08-21 (reversal tarball:
  `/home/node/.hermes/backups/conduit-teardown-20260821-144904.tgz`); don't
  reintroduce a gateway/relay for phone use.
- **`[[keys.command]]` `type = "shell"` commands run with the server's bare
  launchd environment** — no `/opt/homebrew/bin` on PATH, so a command like
  `herdr agent focus atlas` dies silently on command-not-found (detached
  spawn, nothing logged) and the binding looks dead. **Use absolute paths**
  (`/opt/homebrew/bin/herdr …`; both Macs are ARM so the prefix is stable).
  Confirmed 2026-08-18: with an absolute path the binding fires immediately
  after `reload-config` — key changes DO hot-reload; the earlier
  "startup-only" reading was this exact silent failure (herdrdev/herdr#2960,
  corrected upstream). Same PATH blindness: the settings→integrations panel
  probes agent CLIs with the server env, so `codex` reads "not found" even
  when installed — `herdr integration status` from a shell is authoritative.
- **Display-only pane metadata is a supported channel** (`pane.report_metadata`,
  CLI `herdr pane report-metadata`). It overlays presentation without touching
  agent identity or lifecycle: `--display-agent`, `--title`, `--state-label
  STATUS=TEXT` (retitles a state in the `state_text` row), and `--token
  NAME=VALUE` (max 16, `[A-Za-z0-9_-]{1,32}`, rendered as `$name` if the
  `[ui.sidebar.agents] rows` config references it). Every field has a matching
  `--clear-*`, and `--ttl-ms` (max 24h) makes an entry self-expiring, so a
  missed clear can't pin a pane forever. `--state-label` is the cheap one: it
  reuses a row this repo's config already renders, so it needs no config.toml
  change. Verified rendering live 2026-08-25.
  - **Claude Code's `SessionStart` hook reports how a session began** — `startup`
    / `clear` / `resume` / `compact` — which is what makes a *context-free* pane
    detectable. `claude/hooks/herdr-blank-state.sh` maps `startup`+`clear` to a
    `state_labels` override reading "blank", and clears it on `UserPromptSubmit`.
    Two traps: `SessionStart` and `UserPromptSubmit` both **inject hook stdout
    into the model's context**, so such a hook must stay silent on stdout; and
    subagent events carry `agent_id` and must be ignored or they clear the label
    spuriously.
  - **herdr already receives `session_start_source`** — its own integration hook
    sends it on `pane.report_agent_session` — but does not surface it in the
    session snapshot or display it anywhere. The signal is flowing and unused;
    a native "blank" indicator is a reasonable upstream request.
- **Scripting:** NDJSON over `~/.config/herdr/herdr.sock`; `herdr api schema`
  emits the full machine-readable surface. Gotcha: `herdr agent wait --until
  done` never fires on a *focused* pane (done = finished-but-unseen) — wait on
  `idle`/`blocked` or subscribe to `pane.agent_status_changed` events.

### No heredocs in `bin/dot`
The Python that `dot doctor` and `dot bench` run lives in `bin/lib/*.py` as real files.
**Do not "simplify" it back into inline `python3 - <<'PY'` blocks.**

Bash backs a small heredoc with a **pipe** and performs redirections for a compound command
*before* executing anything inside it — so it writes the entire document before forking the
process that would read it. If that write ever blocks it blocks forever, because the only
reader is a process that does not exist yet. This deadlocked `dot doctor` in **~1 of 8 runs**:
hung in the first check, no output, and — the detail that makes it hard to diagnose — **no child
process to blame**. `sample <pid>` parks in `do_redirections → heredoc_write → write`.

Counter-intuitively, **small heredocs are the dangerous ones**; bash switches to a temp file for
large documents, so a 250 KB heredoc is safe where a 2 KB one is not. Payload size sweeps and
isolated pattern reproductions both come back clean — the only reliable reproduction is running
the real command in a loop and counting hangs.

For a payload already in a variable, use process substitution rather than a heredoc:
```bash
done < <(printf '%s\n' "$files")     # safe: writer is a separate process
```
This also keeps the loop in the current shell (a `printf | while` pipeline would subshell it and
lose any counter). Full write-up:
`docs/solutions/runtime-errors/dot-doctor-heredoc-pipe-deadlock-2026-08-07.md`.

`dot check` runs `python3 -m py_compile` over `bin/lib/*.py`, since a syntax error there would
otherwise only surface as a confusing runtime failure of doctor/bench.

### Topgrade config
`topgrade/topgrade.toml` uses the `disable` array under `[misc]` to skip steps.
Variant names must be exact (e.g., `jetbrains_idea`, not `jetbrains`). Run
`topgrade` with an invalid name to see the full list of valid variants.

**Running topgrade from an agent shell (no TTY).** Claude Code's `!` command mode and its
Bash tool have no controlling terminal, so any step that shells out to `sudo` fails with
`a terminal is required to read the password`. `topgrade --dry-run | grep sudo` does **not**
predict this — it lists only topgrade's own commands, and a Homebrew *cask's* upgrade
script can invoke sudo internally (`docker-desktop` does). Set up Touch ID (below), or use
`topgrade --disable brew_cask`, or run it in a real terminal and `tee` the log. Failure is
fail-fast rather than a hang, but a cask can abort *after* unloading services — check what
it removed. Full write-up:
`docs/solutions/security/sudo-in-no-tty-agent-shells-touch-id-2026-08-07.md`.

### Touch ID for sudo
Machine-local root config that **Dotbot cannot manage** (`/etc/pam.d/` is root-owned and
outside `$HOME`), so it is a documented manual step. Needed on every fresh Mac; it is what
makes `sudo` usable from a no-TTY agent shell, since `pam_tid` raises a biometric dialog
instead of asking for a typed password.

```bash
sudo tee /etc/pam.d/sudo_local >/dev/null <<'PAMEOF'
# sudo_local: local config file which survives system update and is included for sudo
auth       optional       /opt/homebrew/lib/pam/pam_reattach.so
auth       sufficient     pam_tid.so
PAMEOF
sudo chmod 444 /etc/pam.d/sudo_local
```

`pam_reattach` (Brewfile: `pam-reattach`) must come **first** — it is what makes Touch ID
work inside **tmux** by reattaching PAM to the GUI session. Without it Touch ID works in a
bare terminal but silently falls back to a password prompt under tmux. It is `optional`, so
a missing module degrades to the password path instead of locking sudo out. `pam_tid` is
`sufficient`, so on success the stack short-circuits before `pam_opendirectory`.

Keep a second terminal with an authenticated sudo session open while editing `/etc/pam.d/` —
a malformed file there can break sudo auth, and that session is the escape hatch.
Undo: `sudo rm /etc/pam.d/sudo_local`. Does not work over SSH (no sensor).

**Rejected alternatives** (do not reintroduce): `SUDO_ASKPASS` has no effect on plain
`sudo` — only `sudo -A` consults it, and brew calls plain `sudo`. `sudo -v` pre-caching
cannot help either (no TTY to authenticate from, and `tty_tickets` keys the cache to the
originating terminal). A NOPASSWD sudoers entry broad enough to cover cask scripts is
effectively passwordless root.

### `--dry-run` and `DOTFILES_DRY_RUN`
`./install --dry-run` previews every Dotbot directive without applying it — zero
mutations to your *config* (no symlinks, dirs, or shell steps). The one thing the
wrapper does regardless of `--dry-run` is `git submodule sync` + `update --init
--recursive dotbot` (it needs the vendored Dotbot to run at all), so on a
brand-new clone the `dotbot/` submodule is checked out first — a one-time git
operation, not part of the preview. The Dotbot run itself is mutation-free.

- **Dotbot ≥ v1.23.0 handles the flag natively.** The vendored submodule is pinned at v1.24.1 (see `dotbot/` submodule state). All built-in plugins (`link`, `create`, `clean`, `shell`) support dry-run and emit `Would create path / Would create symlink / Would run command` lines instead of executing.
- **The `install` wrapper passes `--dry-run` through** to Dotbot. It also exports `DOTFILES_DRY_RUN=1` as defense-in-depth.
- **Shell blocks are skipped entirely on dry-run** by Dotbot's native plugin behavior, so helper scripts (`install_omz.sh`, `install_tmux.sh`, `install_nvim.sh`, `install_packages.sh`) aren't even invoked.
- The `DOTFILES_DRY_RUN` env-var guards in those helpers are redundant under the normal `./install --dry-run` path but matter when a helper is invoked directly (`bash helpers/install_omz.sh` for manual testing or ad-hoc debugging) — they provide a consistent preview message and prevent mutation in that direct-invocation case.

When adding a new state-mutating helper, keep the env-var guard pattern for direct-invocation safety:
```bash
if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would ..."
  exit 0
fi
```

When bumping the Dotbot submodule, re-verify fresh-host dry-run remains mutation-free:
```bash
FAKE=/tmp/dotbot-dryrun-$$; mkdir -p "$FAKE"
for cfg in dotbot-conf/base.yaml dotbot-conf/linux.yaml; do
  DOTFILES_DRY_RUN=1 HOME="$FAKE" ./dotbot/bin/dotbot -d "$PWD" -c "$cfg" --dry-run
done
find "$FAKE" -mindepth 1 | wc -l   # must be 0 (Library/Caches/com.apple.python noise aside)
rm -rf "$FAKE"
```

### Issue tracking — Linear
Issues live in **Linear**, project `Dotfiles`, team `Villavicencio` (key `VIL`):
https://linear.app/villavicencio/project/dotfiles-74974922348e

Migrated off the GitHub Projects board on 2026-08-20 with zero open issues — the old
board (https://github.com/users/villavicencio/projects/2) and the repo's 44 closed
GitHub issues remain as read-only history. **Never create new GitHub issues**; use
`/ticket` (which drives `mcp__linear__save_issue`) or the Linear UI. The Linear MCP
server is configured globally in `~/.claude.json` (machine-local; personal Mac only —
the work Mac deliberately does not use Linear MCP, work tracking lives in other tools);
its tools are deferred, so load them via ToolSearch first. On the work Mac, `/ticket`'s
MCP path is unavailable — capture dotfiles tickets via the Linear web UI instead.

### Branching & pull requests
Work on a **feature branch and merge via pull request** — this is the default for
this repo, not just ticket work. Avoid committing directly to `master`.

- **Branch per change.** Cut a branch off `master` before starting; name it
  conventionally by type: `feat/…`, `fix/…`, `chore/…`, `docs/…`,
  `style/…` (e.g. `feat/statusline-slider-bars`).
- **One PR per logical change.** Push the branch and open a PR with `gh pr create`;
  let the PR carry the review surface. Keep `master` always-green.
- **Merge, then clean up.** After merge, delete the branch and mark any linked
  Linear issue `Done` (`mcp__linear__save_issue` with the issue id + `state: "Done"`)
  as part of the workflow.
- **Documentation and small changes may go straight to `master`** (relaxed
  2026-08-25) — doc edits, typo fixes, and handoff commits included. The rule
  targets behavior and config changes, where review and a clean history matter.
  When in doubt, branch.
- **PR review is CodeRabbit** (`.coderabbit.yaml` at repo root sets
  `auto_incremental_review: false`, so re-review is requested with an `@coderabbitai review`
  comment rather than fired by every push). Wait for its verdict and for each re-review before
  merging — a stale `CHANGES_REQUESTED` is not permission, and a `Review rate limited` check
  passes by design without any review having run. Full procedure, rate-limit mechanics, and when
  to escalate to `dv:gauntlet` instead: the **Code Review** section of the global CLAUDE.md.

Picking up a board ticket always gets its own branch (never work a ticket on
`master`).

**A docs-only PR skips the install matrix — but not the review.**
`install-matrix.yml` declares `paths-ignore: ['docs/**', '**.md', 'claude/**/*.md']`,
so a markdown-only change never triggers `linux`/`macos`; do not wait for a run that
will never start. **CodeRabbit still reviews it** if the PR is review-eligible — drafts and
`WIP` / `DO NOT MERGE` titles are excluded — and it does have findings on markdown, as it did
on #171. So `mergeStateStatus: CLEAN` is not by itself the merge signal — wait for the
CodeRabbit check to leave `pending` and triage its findings first. `CLEAN` only tells you
nothing is *blocking*; a throttled or still-running review also reads clean.

### Claude Code permissions: one allowlist, not two

**`permissions.allow` is the allowlist. There is no `allowedTools` key** — do not
reintroduce one (discovered 2026-08-07).

`allowedTools` is a legacy top-level key. When both exist, **the legacy key wins
and `permissions.allow` is silently inert.** Nothing warns you: rules in
`permissions.allow` simply never take effect, and the failure looks like "the
rule doesn't work" rather than "the rule isn't being read."

This cost a real debugging session. `Bash(gh pr merge:*)` sat in
`permissions.allow` (added by PR #121) while every merge still prompted, because
the live `allowedTools` list — which had 17 read-only-ish rules and no merge
entry — was the one actually consulted. Adding the same rule to `allowedTools`
fixed it instantly, which is what proved the precedence.

Both lists are now consolidated into `permissions.allow` in
`claude/settings.json`. If a permission rule ever appears to be ignored, check
for a resurrected `allowedTools` **before** assuming the auto-mode classifier is
gating the command.

**This regressed once already, and will again.** On 2026-08-25 the live
`~/.claude/settings.json` was found with `allowedTools` back at 18 rules and
`permissions.allow` down to 1 — #127 silently undone, because the repo copy had
been orphaned from its symlink and nobody was comparing (see "copy-seeded, never
symlinked" above). The consolidation lives in a file three other installers
rewrite, so treat it as a **recurring** hazard, not a closed one: `dot drift` now
warns whenever the legacy key reappears, and
`helpers/migrate_claude_settings.py` folds it back.

Related but distinct: the auto-mode classifier **does** independently block
agent edits to `~/.claude/settings.json` itself, regardless of allow rules. That
is intended — it stops an agent widening its own permissions — and is not the
same mechanism. Permission-file edits are a human job.

**A `*` belongs after the subcommand, never mid-command.** In a `Bash(...)` allow
rule the wildcard matches *anything* at that position — including flags and extra
arguments you never intended to pre-approve — and it approves them with no prompt.
`Bash(mv ~/path/_parked/* ~/path/)` reads like "move the parked versions back," but
the `*` also matches inserted options and additional operands, so the rule blesses a
whole family of `mv` invocations rather than the one it was written for. Write the
exact operands (`Bash(mv ~/path/_parked/2.1.112 ~/path/_parked/2.1.113 ~/path/)`),
or use the trailing prefix form `Bash(cmd:*)` after the subcommand. Corrected in
`.claude/settings.local.json` 2026-08-26 after David flagged it.

The same shape hides in the `Bash(cmd *)` space-star form, which is **not** the
`:*` prefix-match idiom and is broad in exactly this way. `.claude/settings.local.json`
still carries ~35 of them accreted from prompt-time approvals — `Bash(bash *)`,
`Bash(curl *)`, `Bash(git reset *)`, `Bash(brew uninstall *)`, and two
`Bash(ssh … root@openclaw-prod ' *)` entries that pre-approve arbitrary remote
commands on the VPS. Prune on sight; that file is gitignored, so nothing but a
manual pass keeps it honest.

---

## Install pipeline

`./install` runs Dotbot with the layered configs — `dotbot-conf/base.yaml` (shared)
then the platform layer (`dotbot-conf/darwin.yaml` or `dotbot-conf/linux.yaml`) — which
together:

1. Creates required directories under `~/.config/`
2. Writes `~/.zshenv` to set `ZDOTDIR=$HOME/.config/zsh`
3. Installs Oh My Zsh and plugins
4. Symlinks config files into `~/.config/`
5. Runs helper scripts: omz, brew, Brewfile, tmux, nvim, nvm, node (fonts install via Brewfile casks)

Helper scripts are in `helpers/`. Each is independently runnable.

---

## Setting up the work Mac

1. Clone this repo (recommended: `~/Projects/Personal/dotfiles`)
2. Verify architecture: `uname -m` must print `arm64` (check iTerm2 is not set to "Open using Rosetta")
3. Run `./install`
4. Clear stale completions: `rm ~/.zcompdump && exec zsh`
5. Create `~/.gitconfig.local`:
   ```ini
   [user]
       email = <your-work-email>
   ```
6. Create `~/env.sh` with required corporate Vertex AI overrides:
   ```bash
   export CLOUDSDK_PYTHON=/usr/bin/python3
   export GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/<service-account-key>.json
   export ANTHROPIC_VERTEX_PROJECT_ID=<corp-gcp-project>
   export CLAUDE_CODE_USE_VERTEX=1
   export CLOUD_ML_REGION=us-east5
   ```
   Note: `CLOUDSDK_PYTHON` is required because the corporate proxy's SSL interception
   breaks Homebrew Python. System Python (`/usr/bin/python3`) trusts corporate CA certs via Keychain.
7. Switch the git remote to use the `github-work` SSH alias:
   ```bash
   git remote set-url origin git@github-work:villavicencio/dotfiles.git
   ```
   This avoids Tailscale MagicDNS routing GitHub SSH through the home Mac.
8. Add GitHub domains to `/etc/hosts` (Tailscale MagicDNS intercepts DNS):
   ```
   140.82.114.4    github.com
   140.82.114.10   codeload.github.com
   185.199.108.133 objects.githubusercontent.com
   185.199.108.133 raw.githubusercontent.com
   ```

---

## Things intentionally left as-is

- `MYSQL_BIN="/usr/local/mysql/bin"` — MySQL PKG installer uses this path on both architectures, it is not a Homebrew path.
- `git/gitconfig` `core.pager = vim -` — intentional preference; vim is the pager for `log`/etc. (Note: `git diff`/`git show` deliberately route through **delta** via the `[pager]` overrides — `core.pager` staying `vim -` is by design, not an oversight.)
- The tmux session restoration block in `zshrc` — guarded to only run outside tmux and only in iTerm2.
- GCM credential helper entries in `git/gitconfig` — auto-generated by Git Credential Manager, commit separately from other work.
- **Linux Dotbot layer + helper branches** (`dotbot-conf/linux.yaml`, the `uname`-guarded locale step in `dotbot-conf/base.yaml`, `case Linux)` in `./install`, `uname` guards in `helpers/*`) — preserved post-VPS-decommission (2026-05-21) as generic infrastructure for any future Linux target. Revival path: retire-noted runbook at `docs/solutions/cross-machine/vps-dotfiles-target.md`.

## Forge Identity
forge-project-key: dotfiles
