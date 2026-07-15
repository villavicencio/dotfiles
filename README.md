# Dotfiles

[![install-matrix](https://github.com/villavicencio/dotfiles/actions/workflows/install-matrix.yml/badge.svg)](https://github.com/villavicencio/dotfiles/actions/workflows/install-matrix.yml)

Personal macOS dotfiles — the single source of truth for two Macs (a primary
personal machine and a corporate-managed work machine). Managed by
[Dotbot](https://github.com/anishathalye/dotbot): idempotent symlinking plus a
handful of helper scripts that install Homebrew packages, Oh My Zsh, tmux/nvim
plugins, Nerd Fonts, and a gitleaks pre-commit hook.

## Install

```sh
git clone https://github.com/villavicencio/dotfiles.git ~/Projects/Personal/dotfiles
cd ~/Projects/Personal/dotfiles
./install
```

`./install` runs a shared `dotbot-conf/base.yaml` then the platform layer
(`dotbot-conf/darwin.yaml` on macOS, `dotbot-conf/linux.yaml` on Linux) automatically. Preview the Dotbot changes without applying them (after the
one-time Dotbot submodule init the wrapper always does):

```sh
./install --dry-run
```

The dry run previews every Dotbot directive (links, created dirs, shell steps)
without applying any of them. One caveat: the `install` wrapper first
syncs/initializes its vendored Dotbot submodule, so on a brand-new clone the
`dotbot/` submodule gets checked out (a one-time git operation) before the
preview runs — the *config* is untouched, but that submodule init is not itself
a dry run. After a first install, make zsh your default shell and re-login:

```sh
chsh -s "$(which zsh)"
```

## The `dot` command

`bin/dot` (symlinked to `~/.local/bin/dot`) is a small dispatcher for common
operations — no new dependencies:

| Command | What |
|---|---|
| `dot doctor` | read-only health check (symlinks resolve, OMZ/TPM plugins, brew bundle, alias binaries, gitleaks on tracked files, INDEX/HANDOFF freshness, toolchain shadowing). Exits non-zero on any failure; makes no changes. |
| `dot check` | static checks — `shellcheck` + `zsh -n`/`bash -n` + a Dotbot dry-run parse. A local mirror of what CI would reject. |
| `dot bench` | 10× interactive-`zsh` startup; prints the distribution and median/max against the 300 ms budget. |
| `dot explain <name>` | locate and print an alias / function / key-binding definition. |
| `dot drift` | package/global-install drift report (`helpers/report_drift.sh`). |
| `dot docs-index` | regenerate `docs/solutions/INDEX.md`. |
| `dot install [args…]` | passthrough to `./install`. |
| `dot update` | `topgrade`. |

## Layout

| Path | What |
|---|---|
| `brew/` | `Brewfile` — all Homebrew formulae and casks |
| `zsh/` | `zshenv`, `zshrc`, `alias.sh`, `functions.sh`, `functions/` |
| `git/` | `gitconfig`, `gitignore`, `gitattributes` |
| `nvim/` | Neovim config (`custom/` symlinked into `~/.config/nvim/`) |
| `tmux/` | tmux config, status-bar scripts, window-meta persistence |
| `starship/` | Starship prompt config |
| `iterm/` | iTerm2 profile settings |
| `helpers/` | install scripts run by the Dotbot pipeline |
| `claude/` | Claude Code config, statusline, hooks (symlinked into `~/.claude/`) |
| `docs/` | solution write-ups (`docs/solutions/`) and planning artifacts |
| `ci/` | CI assets (Dockerfile for the install-matrix workflow) |

## Machine-specific overrides (not tracked)

- **`~/env.sh`** — sourced last in `zshrc`; local-only exports, aliases, `PATH`.
- **`~/.gitconfig.local`** — included at the end of `git/gitconfig`; set a
  work email here to override the personal default.
- **`~/.ssh/config`** — per-machine host aliases live here; not tracked.

## Conventions

- Never hardcode `/Users/<name>` (use `$HOME`) or a Homebrew prefix (use
  `$BREW_PREFIX`, set from `uname -m` at shell startup).
- Every commit is scanned by gitleaks via a pre-commit hook (installed by
  `helpers/install_pre_commit.sh`).
- Work on a feature branch and merge via PR; keep `master` green.

See [`CLAUDE.md`](CLAUDE.md) for the full conventions and the two-machine setup
runbook.

## License

[MIT](LICENSE).
