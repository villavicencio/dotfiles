# Dotfiles

This repo is the single source of truth for two Macs:

| Machine | OS | Hardware | Role |
|---|---|---|---|
| personal | macOS Tahoe | M-series | Primary, source of truth |
| work | macOS Sequoia | M-series | FedEx managed |

Managed by [Dotbot](https://github.com/anishathalye/dotbot). Run `./install` to set up a machine.

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
  commands/     Claude Code slash commands (ticket, handoff, pickup, review-claudemd, reddit)
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
Three states: `waiting` (yellow warning glyph), spinner frame (orange star
cycling at 150ms), or unset (no icon). The spinner runs as a disowned bash
subshell tagged `claude-spinner-marker-<pane>` so `pkill` can find leaks.
It self-terminates when (a) the sentinel file is removed, (b) Claude Code's
PID is gone, or (c) the 5-minute safety cap is hit. If a leaked loop ever
shows up, kill it via `pkill -f claude-spinner-marker`.

### OMZ plugin sync
When adding an Oh My Zsh plugin to the `plugins=()` list in `zshrc`, also add the corresponding
`git clone` to `helpers/install_omz.sh` so it gets installed on fresh machines.

### Topgrade config
`topgrade/topgrade.toml` uses the `disable` array under `[misc]` to skip steps.
Variant names must be exact (e.g., `jetbrains_idea`, not `jetbrains`). Run
`topgrade` with an invalid name to see the full list of valid variants.

### Project board
GitHub Project board: https://github.com/users/villavicencio/projects/2
Use the `/ticket` command to create issues linked to the board.

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

## Things intentionally left as-is

- `MYSQL_BIN="/usr/local/mysql/bin"` — MySQL PKG installer uses this path on both architectures, it is not a Homebrew path.
- `git/gitconfig` `core.pager = vim -` — intentional preference.
- The tmux session restoration block in `zshrc` — guarded to only run outside tmux and only in iTerm2.
- GCM credential helper entries in `git/gitconfig` — auto-generated by Git Credential Manager, commit separately from other work.

## Forge Identity
forge-project-key: dotfiles
