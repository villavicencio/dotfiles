# Dotfiles

This repo is the single source of truth for two Macs and one VPS:

| Machine | OS | Hardware | Role |
|---|---|---|---|
| personal | macOS Tahoe | M-series | Primary, source of truth |
| work | macOS Sequoia | M-series | FedEx managed |
| vps (openclaw-prod) | Ubuntu 24.04 | Hetzner VPS | OpenClaw + Forge host |

Managed by [Dotbot](https://github.com/anishathalye/dotbot). Run `./install` to set up a machine — the wrapper picks `install.conf.yaml` on Darwin and `install-linux.conf.yaml` on Linux automatically.

---

## Structure

```
brew/           Brewfile for all Homebrew packages and casks
btop/           btop system monitor config
docs/           Solution documentation (docs/solutions/<category>/)
fonts/          Nerd fonts installed by helpers/install_fonts.sh
git/            gitconfig, gitignore, gitattributes
helpers/        Bash scripts called by the install pipeline
iterm/          iTerm2 preferences (exported plist, includes Shift+Enter key mapping)
lazygit/        lazygit config
npm/            npm global package list (npm-requirements.txt)
nvim/           Neovim config (custom/ is symlinked into ~/.config/nvim/)
osx/            macOS defaults scripts
starship/       Starship prompt config (command_timeout is a global top-level key)
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
  commands/     Claude Code slash commands (handoff, pickup, review-claudemd, reddit)
  CLAUDE.md     Global Claude Code instructions (symlinked to ~/.claude/CLAUDE.md)
  settings.json Claude Code settings — plugins, allowed tools (symlinked to ~/.claude/settings.json)
```

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
The personal email (`villavicencio.david@gmail.com`) is the default. The work Mac needs:

```ini
# ~/.gitconfig.local
[user]
    email = david.villavicencio@fedex.com
```

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

### NVM lazy loader shims
NVM is lazy-loaded for startup speed. Any npm-globally-installed CLI (e.g., `claude`) must be
added as a shim in the NVM lazy loader block in `zshrc`, or it won't be on PATH until `node`
is first called. When adding a new global CLI: add its name to the `unset -f` line in `_load_nvm()`
and add a `<tool>() { _load_nvm; <tool> "$@"; }` shim.

Current shims: `nvm`, `node`, `npm`, `npx`.

Note: `claude` is installed as a native Homebrew cask (`claude-code`), not via npm, so it
does not need an NVM shim.

### tmux-window-namer skill
`claude/skills/tmux-window-namer/SKILL.md` is a Claude Code skill that renames
tmux windows with a glyph + curated palette color. It stores per-window state in
two tmux user options (`@win_glyph`, `@win_glyph_color`) read by the ternary in
`tmux/tmux.display.conf`'s `window-status-format`. Title text always uses default
tmux colors so inactive tabs naturally dim — only the glyph carries palette color.
Persistence is a JSON sidecar at `~/.config/tmux/window-meta.json`, written by
`tmux/scripts/save-window-meta.sh` and re-applied on every client attach via
`tmux/scripts/restore-window-meta.sh` (wired up in `tmux/tmux.general.conf`
with `set-hook -g client-attached`). Palettes live in
`claude/skills/tmux-window-namer/references/palettes.md` — the skill may only
use hex codes from that file.

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

### Session-start briefing hook
`claude/hooks/session-briefing.sh` is invoked by a SessionStart hook in
`claude/settings.json` with `matcher: "startup"`. Its stdout is concatenated
into the model's first-turn `additionalContext`, giving the same opening
orientation the user used to load by typing `/pickup`. Sections: HANDOFF.md
title + intro + What's Next, current git context, counts of recently-modified
`docs/{brainstorms,plans,solutions}/` files, **and the Forge bridge** (when
cwd's `CLAUDE.md` declares `forge-project-key:`) — `_shared/patterns.md` tail,
project cadence-log tail, full inbox-message content (capped at 2 files +
"...N more" hint), full pending-ticket content (same cap). The Forge bridge
mirrors `claude/commands/pickup.md` Step 2c (single SSH call, delimited
blocks); what stays behind explicit `/pickup` is the *destructive* / interactive
work: inbox archival, ticket promotion to GH issues, VPS health snapshot.
Budget: ~9.5KB output ceiling (under Claude Code's 10k char cap), ~3s typical
wall clock dominated by the SSH connection. Self-truncation footer activates
if any single session pushes the output over budget. Repo-agnostic, never
errors, always exits 0; SSH unreachable degrades to a one-line note. Full
design rationale and budget reasoning in
`docs/solutions/best-practices/claude-code-hooks-and-session-start-2026-04-27.md`.

### OMZ plugin sync
When adding an Oh My Zsh plugin to the `plugins=()` list in `zshrc`, also add the corresponding
`git clone` to `helpers/install_omz.sh` so it gets installed on fresh machines.

### Topgrade config
`topgrade/topgrade.toml` uses the `disable` array under `[misc]` to skip steps.
Variant names must be exact (e.g., `jetbrains_idea`, not `jetbrains`). Run
`topgrade` with an invalid name to see the full list of valid variants.

### `--dry-run` and `DOTFILES_DRY_RUN`
`./install --dry-run` is a true preview: zero filesystem mutations on any host, including a fresh bootstrap.

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
DOTFILES_DRY_RUN=1 HOME="$FAKE" ./dotbot/bin/dotbot -d "$PWD" -c install-linux.conf.yaml --dry-run
find "$FAKE" -mindepth 1 | wc -l   # must be 0
rm -rf "$FAKE"
```

### Project board
GitHub Project board: https://github.com/users/villavicencio/projects/2

---

## Install pipeline

`./install` runs Dotbot with `install.conf.yaml`, which:

1. Creates required directories under `~/.config/`
2. Writes `~/.zshenv` to set `ZDOTDIR=$HOME/.config/zsh`
3. Installs Oh My Zsh and plugins
4. Symlinks config files into `~/.config/`
5. Runs helper scripts: omz, brew, Brewfile, tmux, nvim, fonts, nvm, node

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
       email = david.villavicencio@fedex.com
   ```
6. Create `~/env.sh` with required FedEx/Vertex AI overrides:
   ```bash
   export CLOUDSDK_PYTHON=/usr/bin/python3
   export GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/fxei-meta-project-35631b0c2409.json
   export ANTHROPIC_VERTEX_PROJECT_ID=fxei-meta-project
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

## Setting up a Linux host (VPS)

Ubuntu 24.04 assumed. Root user expected. See
[docs/solutions/cross-machine/vps-dotfiles-target.md](docs/solutions/cross-machine/vps-dotfiles-target.md)
for the full runbook, including Tailscale OAuth + ACL setup for
GitHub Actions sync.

1. Install git + zsh: `apt-get update && apt-get install -y git zsh`
2. Clone: `git clone https://github.com/villavicencio/dotfiles.git ~/.dotfiles`
3. Preview: `cd ~/.dotfiles && ./install --dry-run`
4. Apply: `./install`
5. (Optional) Create `~/.gitconfig.local` with `safe.directory` entries
   for any Docker volumes you run git against. Note the security trade-off
   documented in the runbook.
6. (Optional) Create `~/env.sh` for host-specific exports.

The `./install` wrapper routes to `install-linux.conf.yaml` automatically
based on `uname`. Linux skips: Homebrew, fonts, NVM/Node, chsh, `~/.claude/*`.

---

## Things intentionally left as-is

- `MYSQL_BIN="/usr/local/mysql/bin"` — MySQL PKG installer uses this path on both architectures, it is not a Homebrew path.
- `git/gitconfig` `core.pager = vim -` — intentional preference.
- The tmux session restoration block in `zshrc` — guarded to only run outside tmux and only in iTerm2.
- GCM credential helper entries in `git/gitconfig` — auto-generated by Git Credential Manager, commit separately from other work.
- **Tailscale `tag:prod` grants SSH-root access from `tag:gh-actions`** (the GitHub Actions sync runner). Applying `tag:prod` to a new node auto-extends that grant. Review `docs/solutions/cross-machine/vps-dotfiles-target.md` ACL block before tagging a new node.

## Forge Identity
forge-project-key: dotfiles
