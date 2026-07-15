# AGENTS.md — dotfiles

Tool-neutral brief for any coding agent (Codex, Claude Code, Cursor, …) working in
this repository. It is the canonical description of how the repo is laid out, the
conventions every change must follow, and how to verify a change before committing.

> **Claude Code note:** `CLAUDE.md` carries the same conventions plus Claude-specific
> behavior; it is self-sufficient on its own. This file is the tool-neutral source of
> truth — when the two ever diverge, treat this file's conventions as authoritative and
> reconcile `CLAUDE.md` to match.

---

## What this repo is

Personal dotfiles — the single source of truth for two Macs, managed by
[Dotbot](https://github.com/anishathalye/dotbot).

| Machine | OS | Hardware | Role |
|---|---|---|---|
| personal | macOS Tahoe | M-series | Primary, source of truth |
| work | macOS Sequoia | M-series | corporate-managed |

`./install` sets up a machine — the wrapper runs a shared `dotbot-conf/base.yaml` then the
platform layer (`dotbot-conf/darwin.yaml` on Darwin, `dotbot-conf/linux.yaml` on Linux).
There is no active Linux target as of 2026-05-21 (the Hetzner VPS was repurposed); the Linux
layer and `uname` guards are kept as generic infrastructure — see
`docs/solutions/cross-machine/vps-dotfiles-target.md`.

---

## Layout

```
brew/       Brewfile — all Homebrew formulae and casks
btop/       btop system monitor config
ci/         CI assets (Dockerfile for the install-matrix workflow)
docs/       Compound-engineering artifacts:
            - docs/brainstorms/  requirements docs
            - docs/ideation/     idea-survival outputs
            - docs/plans/        implementation plans
            - docs/solutions/    documented solutions to past problems, with YAML
                                 frontmatter (module, tags, problem_type) + INDEX.md
git/        gitconfig, gitignore, gitattributes
helpers/    Bash scripts called by the install pipeline (each independently runnable)
iterm/      iTerm2 preferences
lazygit/    lazygit config
nvim/       Neovim config (custom/ is symlinked into ~/.config/nvim/)
starship/   Starship prompt config (command_timeout is a global top-level key)
tmux/       tmux config + status-bar scripts + window-meta persistence
topgrade/   Topgrade system-updater config
vale/       Vale prose linter config
zsh/        zshenv (env/PATH/BREW_PREFIX), zshrc, alias.sh, functions.sh, functions/
claude/     Claude Code config: CLAUDE.md, settings.json, statusline, hooks/
            (all symlinked into ~/.claude/)
bin/        Repo CLI — bin/dot (symlinked to ~/.local/bin/dot)
```

---

## Non-negotiable conventions

Every change must hold to these. Violations are what the pre-commit hook, CI, and
`dot doctor` exist to catch.

### Paths — never hardcode
- **User home:** use `$HOME`, never `/Users/<name>/`.
- **Homebrew prefix:** use `$BREW_PREFIX`, never `/opt/homebrew/` or `/usr/local/`.
  `BREW_PREFIX` is set at shell startup from `uname -m` (Apple Silicon → `/opt/homebrew`,
  Intel → `/usr/local`). Call `brew` directly; never rely on `$HOMEBREW_BREW_FILE`.
- `excludesfile`/`attributesfile` in gitconfig point at `~/.config/git/` (XDG, symlinked
  by Dotbot) — do not revert to repo-relative paths.

### zshenv must stay POSIX-safe
`zsh/zshenv` is `.`-sourced by `sh`/`dash`/`bash` during `./install` (not just by zsh).
zsh-only syntax (e.g. `${var:A:h}` modifiers) is a **fatal "bad substitution"** under
dash and breaks the installer. Guard any zsh-only construct on `[ -n "$ZSH_VERSION" ]`
with a POSIX fallback.

### Machine-specific values go in untracked local files
- **`~/env.sh`** — sourced last in `zshrc` (`2>/dev/null`); local-only exports/aliases/PATH.
- **`~/.gitconfig.local`** — included at the end of `git/gitconfig`; set a work email here.
- **`~/.ssh/config`** — per-machine host aliases; not tracked.

### Secret hygiene
Every commit is scanned by **gitleaks** via a pre-commit hook (`.pre-commit-config.yaml`,
wired by `helpers/install_pre_commit.sh`, run automatically by `./install`). Only **staged
diffs** are scanned — not the full tree or history.
- Provider rules have an **entropy gate**: a zero-entropy fake like `ghp_aaaa…` is *not*
  flagged by design. Smoke-test with a high-entropy fake.
- **False positive?** Add an inline `# gitleaks:allow` comment, or a `.gitleaks.toml`
  allowlist entry.
- **Intentional bypass:** `git commit --no-verify` — and document *why* in the commit body.
- The gitleaks version is pinned in **two** places that must match: `rev:` in
  `.pre-commit-config.yaml` and `GITLEAKS_VERSION` in `helpers/install_pre_commit.sh`.
- Local override `pass_filenames: false` is required — see `CLAUDE.md` for the upstream
  gotcha it works around.

### Post-installer audit
After any third-party installer touches shell config (gcloud, rustup, …), run `git diff`
and fix hardcoded `/Users/<name>` → `$HOME`, unstable paths (`~/Downloads`, `/tmp`), and
POSIX `. ` sourcing → the `[[ -f … ]] &&` guard pattern before committing.

---

## Adding things (common tasks)

### Add a Homebrew package
1. Add the formula/cask to `brew/Brewfile` (`brew "<name>"` or `cask "<name>"`).
2. Install it: `brew bundle --file=brew/Brewfile` (installs anything missing; idempotent).
3. Verify: `brew bundle check --file=brew/Brewfile` prints "dependencies are satisfied".
4. `dot doctor` also reports unmet Brewfile entries. Commit `brew/Brewfile`.

### Add a global npm CLI
Add it to `npm/npm-requirements.txt`. If the CLI must be on `PATH` before `node` is first
called, add an NVM lazy-loader shim in `zshrc` (see below) — otherwise it won't resolve
until the loader fires.

### Add an Oh My Zsh plugin
Add it to the `plugins=()` list in `zshrc` **and** add the matching `git clone` to
`helpers/install_omz.sh`, so fresh machines get it.

### Add a lazy loader (FZF/pyenv/NVM/RVM pattern)
Copy an existing `_load_X` block. Direct-sourcing heavy tools (NVM alone is +200–400 ms)
blows the shell-startup budget — the lazy pattern keeps `zsh -i -c exit` under 300 ms.
Use `command <tool>` (not bare `<tool>`) after `_load_*` to avoid infinite shim recursion.

### Add a global CLI behind the NVM shim
NVM is lazy-loaded. Add the CLI's name to the `unset -f` line in `_load_nvm()` and add a
`<tool>() { _load_nvm; <tool> "$@"; }` shim. Current shims: `nvm node npm npx bb browse`.
(`claude` needs no shim — it is not an npm global; `helpers/install_claude_code.sh`
installs it via Anthropic's native installer to `~/.local/bin/claude`, which `zshenv`
puts ahead of Homebrew on `PATH`. The Brewfile does not manage it — the Homebrew cask
lags, so the native installer plus Claude Code's own auto-updater is preferred.)

### Add a state-mutating install helper
Keep the dry-run guard so direct invocation stays previewable:
```bash
if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then echo "[dry-run] would ..."; exit 0; fi
```

### Bump Node
`NODE_VERSION` lives in `zsh/zshenv` (consumed by `helpers/install_node.sh`).

---

## Verifying a change

Run these before committing. `bin/dot` (`~/.local/bin/dot` once installed) wraps most of them.

| Check | Command | Passing bar |
|---|---|---|
| Shell syntax | `zsh -n zsh/*.sh zsh/zshrc zsh/zshenv` / `bash -n helpers/*.sh` | no output |
| Lint | `shellcheck -S warning helpers/*.sh bin/dot` | clean |
| All static | `dot check` | mirrors CI; exit 0 |
| Health | `dot doctor` | exit 0 (read-only; makes no changes) |
| Startup budget | `dot bench` | median < 300 ms |
| Dry-run is mutation-free | see below | 0 entries created |
| Homebrew | `brew bundle check --file=brew/Brewfile` | satisfied |

**Dry-run must never mutate config.** `./install --dry-run` previews Dotbot directives
without applying them. The only thing the wrapper does regardless is init the vendored
`dotbot/` submodule (a one-time git op). Verify a fresh host stays clean:
```bash
FAKE=/tmp/dotbot-dryrun-$$; mkdir -p "$FAKE"
for cfg in dotbot-conf/base.yaml dotbot-conf/linux.yaml; do
  DOTFILES_DRY_RUN=1 HOME="$FAKE" ./dotbot/bin/dotbot -d "$PWD" -c "$cfg" --dry-run
done
find "$FAKE" -mindepth 1 | wc -l   # must print 0
rm -rf "$FAKE"
```
CI (`.github/workflows/install-matrix.yml`) runs the full installer on macOS + Linux and
asserts outcomes; keep both legs green.

---

## Branching & pull requests

Work on a **feature branch and merge via PR** — the default for this repo, not just for
tickets. Avoid committing directly to `master`.
- **Branch per change**, named by type: `feat/…`, `fix/…`, `chore/…`, `docs/…`, `style/…`.
- **One PR per logical change**; push and open with `gh pr create`. Keep `master` green.
- **Merge, then clean up**: delete the branch, close any linked issue (`gh issue close`).
- **Trivial exceptions** (typo, one-line doc tweak) may go straight to `master`.

Project board: https://github.com/users/villavicencio/projects/2

---

## Install pipeline (what `./install` does)

Runs Dotbot with the platform config, which: (1) creates `~/.config/` dirs; (2) writes
`~/.zshenv` setting `ZDOTDIR=$HOME/.config/zsh`; (3) installs Oh My Zsh + plugins;
(4) symlinks config into `~/.config/`; (5) runs the `helpers/` scripts (omz, brew,
Brewfile, tmux, nvim, nvm, node). Each helper is independently runnable. (Nerd Fonts
install via Homebrew casks in `brew/Brewfile`, not a helper.)

---

## Invariants & gotchas (do not "fix" these)

- **Otty / tool-managed shell-rc blocks** — some blocks in the shell rc files are managed
  by their own tools and must not be reformatted or absorbed into repo conventions.
- **`git/gitconfig` `core.pager = vim -`** is intentional; `diff`/`show` route through
  **delta** via the `[pager]` overrides.
- **GCM credential-helper entries** in `git/gitconfig` are auto-generated — commit them
  separately from other work.
- **`MYSQL_BIN="/usr/local/mysql/bin"`** is the MySQL PKG installer path on both
  architectures — not a Homebrew path, do not `$BREW_PREFIX` it.
- **Linux Dotbot config + `uname` guards** are preserved post-VPS-decommission as generic
  infrastructure for any future Linux target.
- The **tmux session-restoration block** in `zshrc` is guarded to run only outside tmux and
  only in iTerm2.

Deeper write-ups for past bugs and decisions live in `docs/solutions/` (grouped by
category, indexed in `docs/solutions/INDEX.md`). Consult it before re-deriving a fix.
