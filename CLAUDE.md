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
fonts/          Nerd fonts installed by helpers/install_fonts.sh
git/            gitconfig, gitignore, gitattributes
helpers/        Bash scripts called by the install pipeline
iterm/          iTerm2 preferences (exported plist)
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
  commands/     Claude Code slash commands (ticket, handoff, pickup, review-claudemd)
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

### Node version
`NODE_VERSION` is defined in `zsh/zshenv` and used by `helpers/install_node.sh`.
Update it there whenever upgrading Node.

### NVM lazy loader shims
NVM is lazy-loaded for startup speed. Any npm-globally-installed CLI (e.g., `claude`) must be
added as a shim in the NVM lazy loader block in `zshrc`, or it won't be on PATH until `node`
is first called. When adding a new global CLI: add its name to the `unset -f` line in `_load_nvm()`
and add a `<tool>() { _load_nvm; <tool> "$@"; }` shim.

### OMZ plugin sync
When adding an Oh My Zsh plugin to the `plugins=()` list in `zshrc`, also add the corresponding
`git clone` to `helpers/install_omz.sh` so it gets installed on fresh machines.

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
4. Create `~/.gitconfig.local`:
   ```ini
   [user]
       email = david.villavicencio@fedex.com
   ```
5. Create `~/env.sh` with required FedEx/Vertex AI overrides:
   ```bash
   export CLOUDSDK_PYTHON=/usr/bin/python3
   export GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/fxei-meta-project-35631b0c2409.json
   export ANTHROPIC_VERTEX_PROJECT_ID=fxei-meta-project
   export CLAUDE_CODE_USE_VERTEX=1
   export CLOUD_ML_REGION=us-east5
   ```
   Note: `CLOUDSDK_PYTHON` is required because the corporate proxy's SSL interception
   breaks Homebrew Python. System Python (`/usr/bin/python3`) trusts corporate CA certs via Keychain.

---

## Things intentionally left as-is

- `MYSQL_BIN="/usr/local/mysql/bin"` — MySQL PKG installer uses this path on both architectures, it is not a Homebrew path.
- `git/gitconfig` `core.pager = vim -` — intentional preference.
- The tmux session restoration one-liner in `zshrc` — runs on every shell start by design.
- GCM credential helper entries in `git/gitconfig` — auto-generated by Git Credential Manager, commit separately from other work.
