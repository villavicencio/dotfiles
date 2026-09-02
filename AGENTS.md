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
herdr/      Herdr agent-multiplexer config (config.toml symlinked into ~/.config/herdr/)
iterm/      iTerm2 preferences
lazygit/    lazygit config
nvim/       Neovim config (custom/ is symlinked into ~/.config/nvim/)
otty/       Otty terminal config + iTerm2-imported theme (copy-seeded, NOT symlinked)
starship/   Starship prompt config (command_timeout is a global top-level key)
tmux/       tmux config + status-bar scripts + window-meta persistence
topgrade/   Topgrade system-updater config
vale/       Vale prose linter config
zsh/        zshenv (env/PATH/BREW_PREFIX), zshrc, alias.sh, functions.sh, functions/
claude/     Claude Code config, delivered into ~/.claude/ two different ways:
            CLAUDE.md, statusline, hooks/  → symlinked
            settings.json                  → COPY-SEEDED, never symlinked (see gotchas)
bin/        Repo CLI — bin/dot (symlinked to ~/.local/bin/dot)
            bin/lib/*.py — Python helpers for doctor/bench, deliberately NOT heredocs
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
Add it to `npm/npm-requirements.txt` (registry-installable packages only — an `npm link`ed
local package like `browse-gateway`/`obscura` cannot be installed from that manifest). If it
was installed under the **highest installed** node version — the usual case — it is already on
`PATH` in a fresh shell via the lazy-loader's node-bin prepend and needs no shim. See the
shim section below for the exception.

### Add an Oh My Zsh plugin
Add it to the `plugins=()` list in `zshrc` **and** add the matching `git clone` to
`helpers/install_omz.sh`, so fresh machines get it.

### Add a lazy loader (FZF/pyenv/NVM/RVM pattern)
Copy an existing `_load_X` block. Direct-sourcing heavy tools (NVM alone is +200–400 ms)
blows the shell-startup budget — the lazy pattern keeps `zsh -i -c exit` under 300 ms.
Use `command <tool>` (not bare `<tool>`) after `_load_*` to avoid infinite shim recursion.

### Add a vendor-installed CLI (uv, Claude Code)
Some tools ship via their vendor's installer into `~/.local/bin` rather than the Brewfile,
because `zshenv` puts that dir ahead of Homebrew — a brewed copy would be permanently
shadowed — and because they self-update. `helpers/install_uv.sh` and
`helpers/install_claude_code.sh` are the two; both skip when already present.
When adding another, check whether its installer edits shell rc files and suppress that
(uv needs `UV_NO_MODIFY_PATH=1`): `.zshrc`/`.zshenv` are Dotbot symlinks into this repo, so
an unguarded installer dirties tracked files.

### NVM lazy-loader shims
A globally-installed npm CLI needs **no** NVM shim — the lazy-loader block prepends the default
node version's `bin` dir to `PATH` at startup, and `#!/usr/bin/env node` shebangs resolve through
it, so the CLI works in a fresh shell with nvm unloaded. Only add a shim for a global installed
under a node version other than the highest installed one — the prepend resolves
`sort -V | tail -1`, NOT nvm's `alias/default`, and the two can diverge.
Current shims: `nvm node npm npx` (nvm's own commands).
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
- **Merge, then clean up**: delete the branch, mark any linked Linear issue `Done`.
- **Trivial exceptions** (typo, one-line doc tweak) may go straight to `master`.
- **Docs-only PRs skip the install matrix, not the review** — `install-matrix.yml` sets
  `paths-ignore: ['docs/**', '**.md', 'claude/**/*.md']`, so a markdown-only change never
  triggers `linux`/`macos`; don't wait for a run that will never start. CodeRabbit still
  reviews markdown on any review-eligible PR (drafts and `WIP` / `DO NOT MERGE` titles are
  excluded), so wait for its check to leave `pending` and triage the findings —
  `mergeStateStatus: CLEAN` also reads clean while a review is pending or throttled.

Issue tracking: Linear, project `Dotfiles`, team `Villavicencio` (key `VIL`) —
https://linear.app/villavicencio/project/dotfiles-74974922348e (migrated off the
GitHub Projects board 2026-08-20; the board and closed GitHub issues are read-only
history — never create new GitHub issues).

- **PR review is CodeRabbit** (`.coderabbit.yaml` at repo root sets
  `auto_incremental_review: false`, so re-review is requested with an `@coderabbitai review`
  comment rather than fired by every push). Wait for its verdict and for each re-review before
  merging — a stale `CHANGES_REQUESTED` is not permission, and a `Review rate limited` check
  passes by design without any review having run. Full procedure, rate-limit mechanics, and when
  to escalate to `dv:gauntlet` instead: the **Code Review** section of the global CLAUDE.md.

---

## Install pipeline (what `./install` does)

Runs Dotbot with the platform config, which: (1) creates `~/.config/` dirs; (2) writes
`~/.zshenv` setting `ZDOTDIR=$HOME/.config/zsh`; (3) installs Oh My Zsh + plugins;
(4) symlinks config into `~/.config/`; (5) runs the `helpers/` scripts (omz, brew,
Brewfile, tmux, nvim, nvm, node). Each helper is independently runnable. (Nerd Fonts
install via Homebrew casks in `brew/Brewfile`, not a helper.)

---

## Invariants & gotchas (do not "fix" these)

- **No heredocs in `bin/dot` — do not inline `bin/lib/*.py` back into `python3 - <<'PY'`.**
  Bash backs a small heredoc with a pipe and writes the *whole* document before forking the
  reader, so a blocked write never clears: the process that would drain the pipe does not
  exist yet. This deadlocked `dot doctor` in ~1 of 8 runs (hung in the first check, no child
  process, no output). Counter-intuitively **small heredocs are the risky ones** — bash uses a
  temp file for large ones. Use a real file, or `< <(printf …)` for variable payloads. Write-up:
  `docs/solutions/runtime-errors/dot-doctor-heredoc-pipe-deadlock-2026-08-07.md`.
- **Otty / tool-managed shell-rc blocks** — some blocks in the shell rc files are managed
  by their own tools and must not be reformatted or absorbed into repo conventions.
- **sudo does not work from an agent shell without Touch ID.** Claude Code's `!` mode and
  Bash tool have no controlling TTY, so any `sudo` fails with "a terminal is required."
  The fix is a one-time root step creating `/etc/pam.d/sudo_local` with `pam_reattach`
  (tmux) + `pam_tid` — documented in `CLAUDE.md` under "Touch ID for sudo"; it cannot be
  Dotbot-managed because `/etc/pam.d/` is root-owned and outside `$HOME`.
  Do **not** substitute `SUDO_ASKPASS` (plain `sudo` ignores it — only `sudo -A` consults
  it), `sudo -v` pre-caching (`tty_tickets` keys the cache to the originating terminal), or
  a NOPASSWD sudoers entry (cask scripts run arbitrary `sudo rm -rf`; that is passwordless
  root). Note `topgrade --dry-run | grep sudo` does not predict which steps need root — a
  cask's own script can invoke sudo internally. Full write-up:
  `docs/solutions/security/sudo-in-no-tty-agent-shells-touch-id-2026-08-07.md`.
- **`herdr/config.toml` IS symlinked — the opposite of Otty, deliberately.** Herdr
  rewrites its config in place (inode-preserving, verified on 0.8.0), so the symlink
  survives and live edits surface as `M herdr/config.toml`; diff and commit them. Link
  only the file — `~/.config/herdr/` also holds the socket, logs, and session state.
  `herdr server stop` / restart kills all pane processes (layout restores, supported
  agent sessions resume); detach instead. `herdr integration install <agent>` writes
  into the agent's own config dir and is a human step, not an agent one (claude and
  codex installed, both v7). Custom `[[keys.command]]` shell commands run
  with the server's bare launchd PATH and fail silently — use absolute paths
  (`/opt/homebrew/bin/herdr …`); key changes themselves hot-reload fine. The ssh shim
  herdr's remote-agent detection depends on — `~/.local/bin/claude-code`, which backs
  `atlas-tools ⚙` and formerly the retired `axiom ∴` — is a repo-tracked auto-reconnect
  wrapper (`herdr/shims/`) seeded by
  `helpers/install_herdr_agents.sh` (darwin.yaml); it execs a same-named raw ssh
  alias in `~/.local/libexec/` (preserving the detected process name) in a retry
  loop, so remote panes survive sleep/network loss and — the fleet "a pane never
  self-closes" rule — drop to an interactive shell on clean detach rather than
  closing. Local agents get the same rule via the pane template
  `["/bin/zsh", "-l", "-c", "claude --continue || claude; exec /bin/zsh -il"]`,
  whose `--continue || claude` pair also relaunches the agent into the **most
  recent session for that working directory** — usually, but not always, the
  pane's own last conversation: where a Claude Code slug is shared with another
  surface, the thread handed back may be that surface's. The bare fallback
  catches a directory with no prior session, where `--continue` exits 1. Full
  caveats: the pane-template section of CLAUDE.md.
  Local project agents (`melos ♪`, `sites ✦`, `borealis ❆`, `argus ◉`,
  `skills ⚒`, `obscura ✇`, `eidos ❖`, `orrery ☉` — roster table in CLAUDE.md)
  need no shim — herdr detects a local claude pane natively; they use the pane
  template above, whose login shell rebuilds PATH from `zshenv` before claude
  starts (the server spawns pane commands with its bare launchd env).
  A local **hermes** pane works the same way — the template with `hermes chat` in
  place of `claude`; herdr's hermes manifest detects the venv process natively, so
  it needs no shim either. (No hermes pane is in the fleet as of 2026-09-01: `atlas`
  and `vice` moved to the official Hermes Desktop app and were retired, along with
  the `hermes-agent` shim they were the only consumers of.)
  `atlas-tools ⚙` (`prefix+t`) is a remote **Claude Code** surface, not a TUI
  attach: the repo lives only at `/home/node/Projects/atlas-tools` on
  openclaw-prod as user `node`, and **no Mac-side checkout exists**. herdr's pane
  `cwd` is always local — it is where the ssh process starts — so a remote working
  directory needs no local clone; the pane command establishes it remotely. It
  reuses the existing `claude-code` ssh alias (detection keys on the ssh child's
  process name, so several panes may share one alias with different args, told
  apart by `herdr agent rename`; it shared the alias with `axiom ∴` until that
  surface retired 2026-09-02). The remote tmux is addressed with
  `-L atlas-tools -f /home/node/.config/tmux/atlas-tools.conf` and `new-session -A`, which
  makes it self-healing across VPS reboots without a systemd unit. The conf file
  is required because tmux defaults `set-titles` to `off` and that option is what
  carries agent state out through a nested tmux — assume it is off on any socket
  until checked, since this repo documented it as on for months while it was not.
  A pane reading `agent_status: unknown` usually has a different cause entirely:
  it has fallen through to the shim's clean-detach `zsh` fallback, so no agent
  process exists to detect. Check `pane.process_info` before blaming detection
  config.
  A pane whose `layout.export` node has no `command` is degraded even though it
  still detects as an agent; rebuild it with `layout.apply` over the socket
  (recipe in CLAUDE.md).
  `orrery ☉` is the **Forge-resident hybrid** pattern (full SOP in CLAUDE.md):
  the project stays Forge-managed, the pane targets the physical
  `~/.forge-projects/<codename>` path (herdr `chdir` resolves symlinks, so
  identity always lands there), `~/Projects/<name>` is an ergonomics-only
  symlink, and both harnesses share one project slug — shared vault memory and
  `--resume` continuity across Forge ACP sessions and the pane.
- **`otty/` is copy-seeded, never symlinked — do not add a `link:` entry for it.**
  `otty config set` and the Settings UI write via temp-file + `rename(2)`, which replaces
  the path and destroys a symlink on the first settings change; the CLI still exits 0 and
  `git status` stays clean, so the repo copy becomes a silently-orphaned stale twin.
  `helpers/install_otty.sh` copies it in only when absent; `dot drift` reports divergence
  by comparing normalized `otty config show` output on both sides. Tracked scope is
  `config.toml` + the user-authored iTerm2-imported theme only — the other 24 themes are
  app-seeded and regenerate. Full write-up:
  `docs/solutions/integration-issues/otty-config-symlink-hostile-atomic-rename-2026-08-07.md`.
- **`claude/settings.json` is copy-seeded too — do not add a `link:` entry for it.**
  Three writers besides this repo rewrite `~/.claude/settings.json` in place: Claude Code
  itself, `herdr integration install`, and Otty's agent-integration installer. A symlink is
  orphaned on the first write, exactly like Otty. This already bit once — the repo copy sat
  stale from 2026-08-07 to 2026-08-25 while the live file regrew a legacy top-level
  `allowedTools` key (18 rules) against a `permissions.allow` of 1, silently re-arming the
  precedence trap PR #127 had removed: when both keys exist the legacy one WINS and
  `permissions.allow` is inert. `helpers/install_claude_settings.sh` seeds when absent and
  `--capture` records live changes back (dropping the machine-local keys `effortLevel`,
  `autoMode`, `mcpServers`, `allowedTools`, and normalizing `$HOME` paths to `~/`).
  `dot drift` compares capture-normalized forms and warns if `allowedTools` reappears.
  Agents cannot write this file — the auto-mode classifier blocks it by design; run
  `helpers/migrate_claude_settings.py` yourself on a machine that predates the scheme.
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
