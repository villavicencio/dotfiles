# Install pipeline and the server profile

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

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

On Windows, `install.ps1` replaces all of the above — see `docs/reference/windows.md`.

## Server profile (`hal`)

`DOTFILES_PROFILE=server ./install` sets up `hal`, a headless Mac mini (macOS 27, Apple
Silicon) reached only over SSH. It runs as the standard account `hal`, which has no sudo and
owns Homebrew at `/opt/homebrew`. An unset profile or `desk` is the normal install. Any other
value fails before Dotbot runs, and so does `server` on anything but macOS.
`DOTFILES_PROFILE=server ./install --dry-run` previews it.

How it differs from a desk Mac:

- **Layers:** `base.yaml` runs with `--except clean`, then `dotbot-conf/server.yaml` runs in
  place of `darwin.yaml`. Dotbot's `clean` only removes dead links in `~` that resolve into
  this repo (`dotbot/src/dotbot/plugins/clean.py`, v1.24.1). hal also carries dangling links
  copied from the VPS, such as `~/personal`, and a first install has nothing to clean, so
  `clean` doesn't run there at all.
- **Packages:** `brew/Brewfile.server`, formulae only plus one CLI-only cask (`vercel`, which
  Homebrew moved out of core; CI allows exactly that one). An old `vercel`/`vercel-cli` formula
  blocks that cask, so `helpers/migrate_vercel_cask.sh` swaps it first, on both profiles.
  Installed by `brew bundle` with
  `HOMEBREW_BUNDLE_NO_UPGRADE=1` and `HOMEBREW_NO_INSTALL_UPGRADE=1`, so installed formulae
  aren't upgraded under running services. A new formula can still upgrade a shared
  dependency it needs. The Homebrew network installer never runs: if brew is missing at
  the `BREW_PREFIX` location (`/opt/homebrew` on Apple Silicon), the wrapper stops before
  Dotbot runs, with nothing changed. No font casks. The container runtime (OrbStack, and brew's `docker` and
  `colima`) is installed out of band and is in no Brewfile.
- **Skipped:**
  - chsh.
  - The nvm, node, uv and Claude Code installers. node and uv come from the Brewfile, and
    Claude Code is installed separately on hal.
  - The Claude settings seed and the `~/.claude` links. `~/.claude` arrives from the VPS with
    regular files in those places.
  - The iTerm profile.
  - The `~/.config/nvim` link and the plugin bootstrap. Without the bootstrap, the first
    `nvim` would rewrite `nvim/lazy-lock.json`, so the server's nvim runs with no config. A
    link into this repo left by an earlier desk install is moved to `~/.config/nvim.pre-dotfiles`
    (`helpers/retire_desk_nvim_link.sh`); a real directory or a link elsewhere is left alone.
- **Kept:** Oh My Zsh, the shared zsh, git and tmux configs, the pre-commit hook, and the
  Codex `AGENTS.md` link. TPM installs the plugins against a private, throwaway tmux socket.
  Its `install_plugins` reads the plugin list from whatever tmux server is current, so a
  server hal already runs without this config would make it abort ("Tmux Plugin Manager not
  configured") and fail the install.
- **Overlays**, linked only under this profile (the tmux one by `base.yaml`, ahead of TPM;
  the others by `server.yaml`):

  | Link | Source | Effect |
  |---|---|---|
  | `~/.config/zsh/.zprofile` | `zsh/zprofile.server` | With `ZDOTDIR` set, zsh no longer reads `~/.zprofile` or `~/.zshrc`. This file carries what hal's own versions did: brew shellenv, OrbStack's `init.zsh`, and `~/.lmstudio/bin`, each only if present. hal's `~/.zprofile` and `~/.zshrc` are left untouched. After shellenv it re-applies `zsh/zshenv`'s PATH order, which shellenv's prepend and macOS's `/etc/zprofile` (`path_helper`) undo in every login shell. |
  | `~/.config/git/gitconfig.platform` | `git/gitconfig.server` | Resets the credential helpers (osxkeychain and GCM can't work over SSH) to `/opt/homebrew/bin/gh` for github.com and gist.github.com, and sets `core.pager = less -FRX`. |
  | `~/.config/tmux/local.conf` | `tmux/local.server.conf` | Sets `@continuum-boot off`. It is linked before the TPM step starts a tmux server, so tmux-continuum never loads with boot on and never writes `~/Library/LaunchAgents/Tmux.Start.plist`, which opens iTerm at login. A regular `local.conf` already there is renamed to `local.conf.dotbot-backup.<timestamp>` first (Dotbot's `backup`). If the link still isn't in place, `install_tmux.sh` fails without starting tmux. |

- **`~/.zshenv`:** a `~/.zshenv` this install didn't write is kept as
  `~/.zshenv.pre-dotfiles` before being replaced. A regular file is copied there, and a
  symlink is moved there as a link.

Verify with `ci/server-profile-checks.sh static` locally. CI's `macos-server` job runs the
profile in a simulated hal home and checks the pre-existing files, the shell chain, git, and
that no LaunchAgent was added. It also checks that a second run changes nothing.
