# AGENTS.md — dotfiles

Tool-neutral brief for any coding agent (Codex, Claude Code, Cursor, …) working in
this repository. It is the canonical description of how the repo is laid out, the
conventions every change must follow, and how to verify a change before committing.

> **Claude Code note:** `CLAUDE.md` carries the same conventions as one-line rules plus
> Claude-specific behavior, and points at `docs/reference/` for the long write-ups (moved
> out of it on 2026-10-22 to cut every session's startup context, VIL-402). This file is
> the tool-neutral source of truth — when the two ever diverge, treat this file's
> conventions as authoritative and reconcile `CLAUDE.md` to match.

---

## What this repo is

Personal dotfiles — the single source of truth for two Macs and a headless Mac mini server,
managed by [Dotbot](https://github.com/anishathalye/dotbot), and a Windows gaming PC, managed
by `install.ps1` (PowerShell, not Dotbot).

| Machine | OS | Hardware | Role |
|---|---|---|---|
| personal | macOS Tahoe | M-series | Primary, source of truth |
| work | macOS Sequoia | M-series | corporate-managed |
| hal | macOS 27 | Mac mini (Apple Silicon) | Headless server, SSH only; `DOTFILES_PROFILE=server ./install`, run as `hal` (see "Server profile (`hal`)") |
| gaming-pc | Windows 11 Pro | Ryzen 7 5800X / RTX 3070 | Gaming; `install.ps1` + `windows/` |
| gaming-pc WSL | Ubuntu 26.04 LTS (WSL 2) | same PC | Linux layer; separate clone inside WSL |

`./install` sets up a machine — the wrapper runs a shared `dotbot-conf/base.yaml` then the
platform layer (`dotbot-conf/darwin.yaml` on Darwin, `dotbot-conf/linux.yaml` on Linux).
The active Linux target is WSL Ubuntu 26.04 on the gaming PC (since 2026-09-24, reinstalled
on 26.04 2026-09-25; setup in `docs/reference/wsl-linux.md`). CI's Linux
leg runs the same release (VIL-154). On 26.04 `sudo` is sudo-rs; CI runs as root, so only
the WSL install exercises it. Linux installs no Node or uv, by design (VIL-157).
The earlier Hetzner VPS target was retired
2026-05-21 — see `docs/solutions/cross-machine/vps-dotfiles-target.md`.

---

## Layout

```
brew/       Brewfile — all Homebrew formulae and casks; Brewfile.server — the server profile's
btop/       btop system monitor config
ci/         CI assets (Dockerfile for the install-matrix Linux leg, PSScriptAnalyzer
            settings for its Windows leg)
docs/       docs/agents/ — procedures behind the global agent instructions (loaded on demand)
            Compound-engineering artifacts:
            - docs/brainstorms/  requirements docs
            - docs/ideation/     idea-survival outputs
            - docs/plans/        implementation plans
            - docs/solutions/    documented solutions to past problems, with YAML
                                 frontmatter (module, tags, problem_type) + INDEX.md
git/        gitconfig, gitignore, gitattributes, gitconfig.linux (Linux overlay, see gotchas)
helpers/    Bash scripts called by the install pipeline (each independently runnable)
iterm/      iTerm2 preferences
lazygit/    lazygit config
nvim/       Neovim config (NvChad v2.5; the whole dir is linked as ~/.config/nvim,
            %LOCALAPPDATA%\nvim on Windows). Plugins pinned in lazy-lock.json
pilot/      hal overnight coding-pilot runner (VIL-396); runs on hal as david, not
            installed by Dotbot. See pilot/README.md
starship/   Starship prompt config (command_timeout is a global top-level key)
tmux/       tmux config + status-bar scripts + window-meta persistence
topgrade/   Topgrade system-updater config
vale/       Vale prose linter config
zsh/        zshenv (env/PATH/BREW_PREFIX), zshrc, alias.sh, functions.sh, functions/
claude/     Claude Code config, delivered into ~/.claude/ two different ways:
            CLAUDE.md, statusline, hooks/  → symlinked
            settings.json                  → COPY-SEEDED, never symlinked (see gotchas)
codex/      Codex global instructions — AGENTS.md symlinked to ~/.codex/AGENTS.md
            (kept short on purpose, like claude/CLAUDE.md; both point at docs/agents/)
bin/        Repo CLI — bin/dot, bin/wt and bin/op-agent (symlinked to ~/.local/bin/)
            bin/lib/*.py — Python helpers for doctor/bench, deliberately NOT heredocs
            bin/lib/cleanup-merged-branch.sh — merged-branch cleanup, sourced by agents and `wt done`
orca.yaml   Orca's setup script for each new worktree: checks out the dotbot submodule and
            copies the files .worktreeinclude names. Never ./install from a worktree (the
            live links would point into it and dangle when it's removed). Removing an Orca
            worktree takes Force delete (git refuses one with a submodule checked out); there
            is deliberately no archive script. After a merge, run cleanup_merged_branch first:
            it deletes the branch and detaches the worktree, since Orca never deletes a
            squash-merged branch. Never `git submodule deinit` in a worktree (it
            unregisters dotbot in the shared .git/config). Details: docs/reference/orca-worktrees.md
.worktreeinclude  gitignored files copied into new worktrees (claude --worktree, wt new, orca.yaml)
windows/    Windows layer, applied by install.ps1 (repo root): packages.json (winget),
            gitconfig (overrides chained after git/gitconfig), powershell/profile.ps1,
            terminal/dotfiles.json (Windows Terminal fragment), claude-settings.json
            (hook-free Claude Code settings seed — COPY-SEEDED like the Mac's); tweaks.ps1
            (system settings, the `defaults write` counterpart; opt-in, not run by install.ps1);
            install_nvim.ps1 (the helpers/install_nvim.sh counterpart)
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
- **`~/.gitconfig.local`** — included at the end of `git/gitconfig` (after the platform
  overlay, so it wins); set a work email here.
- **`~/.ssh/config`** — per-machine host aliases; not tracked.

### Secret hygiene
**This repo is public.** Don't name David's employer or describe what his work agents are for
(Axiom is just "the `axiom` profile"); the audit recipe in
`docs/solutions/best-practices/public-repo-secret-audit-recipe-2026-05-06.md` greps for it.
Gitleaks doesn't catch plain words. Seen 2026-10-21 on #234.

Every commit is scanned by **gitleaks** via a pre-commit hook (`.pre-commit-config.yaml`,
wired by `helpers/install_pre_commit.sh`, run automatically by `./install`). Only **staged
diffs** are scanned — not the full tree or history.
- Provider rules have an **entropy gate**: a zero-entropy fake like `ghp_aaaa…` is *not*
  flagged by design. Smoke-test with a high-entropy fake.
- **False positive?** Add an inline `# gitleaks:allow` comment, or a `.gitleaks.toml`
  allowlist entry.
- **Intentional bypass:** `git commit --no-verify` — and document *why* in the commit body.
- The gitleaks version is pinned in **three** places that must match: `rev:` in
  `.pre-commit-config.yaml`, `GITLEAKS_VERSION` in `helpers/install_pre_commit.sh`, and the
  `Gitleaks.Gitleaks` `Version` in `windows/packages.json`.
- Local override `pass_filenames: false` is required — see `docs/reference/secret-hygiene.md`
  for the upstream gotcha it works around.

### Post-installer audit
After any third-party installer touches shell config (gcloud, rustup, …), run `git diff`
and fix hardcoded `/Users/<name>` → `$HOME`, unstable paths (`~/Downloads`, `/tmp`), and
POSIX `. ` sourcing → the `[[ -f … ]] &&` guard pattern before committing.
An installer that appends to `.zshrc` edits this repo's `zsh/zshrc` (the `$ZDOTDIR` link); a
machine-specific line goes in `~/env.sh` instead (e.g. iTerm2 shell integration on hal).

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
lags, so the native installer plus Claude Code's own auto-updater is preferred. The legacy
`"autoUpdates": false` in `~/.claude.json` does not stop it; `env.DISABLE_AUTOUPDATER = "1"`
in `settings.json` does.)
That order survives only because `zshrc` re-sources `zshenv` after `brew shellenv`, which
(with login shells' `path_helper`) would otherwise put Homebrew and `/usr/bin` first. Keep
that line. On desk Macs, `dot doctor` fails if `claude` doesn't resolve to
`~/.local/bin/claude` or that native install is missing.

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
| Shell syntax | `for f in zsh/*.sh zsh/zshrc zsh/zshenv; do zsh -n "$f"; done` / `for f in helpers/*.sh bin/wt bin/lib/*.sh; do bash -n "$f"; done` (`-n` checks only its first file; later ones become that script's arguments) | no output |
| Lint | `shellcheck -S warning helpers/*.sh bin/dot bin/wt bin/lib/*.sh` | clean |
| All static | `dot check` | mirrors CI; exit 0 |
| Health | `dot doctor` | exit 0 (read-only; makes no changes) |
| Startup budget | `dot bench` | median < 300 ms |
| Dry-run is mutation-free | see below | 0 entries created |
| Homebrew | `brew bundle check --file=brew/Brewfile` | satisfied |
| Server profile | `ci/server-profile-checks.sh static` | exit 0 |
| Merged-branch cleanup (after changing `bin/lib/cleanup-merged-branch.sh` or `wt done`) | `ci/cleanup-merged-branch-checks.sh` | exit 0, both shells (local only, not in CI) |
| `op-agent` guards (after changing `bin/op-agent`) | `ci/op-agent-checks.sh` | exit 0 (local only, stub `op`) |

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
CI (`.github/workflows/install-matrix.yml`) runs the full installer on macOS + Linux (an
Ubuntu 26.04 container from `ci/Dockerfile`, pinned by digest) and
`install.ps1 -SkipPackages` on a hosted Windows runner (no full `winget import`; every
`packages.json` ID is resolved instead, and a runner without winget fails the job rather
than skipping checks), and asserts outcomes; a `macos-server` job runs
`DOTFILES_PROFILE=server ./install` in a simulated hal home. Keep every leg green.
The `windows` job's `EXPECTED_LINKS` list must match `$links` in `install.ps1`.

---

## Branching & pull requests

Work on a **feature branch and merge via PR** — the default for this repo, not just for
tickets. Avoid committing directly to `master`.
- **Branch per change**, named by type: `feat/…`, `fix/…`, `chore/…`, `docs/…`, `style/…`.
  A ticket's branch carries its id after the type: `feat/vil-522-statusline-ticket`. The
  statusline shows the id as a link to the issue.
- **One PR per logical change**; push and open with `gh pr create`. Keep `master` green.
- **Merge, then clean up**: delete the branch, mark any linked Linear issue `Done`.
- **Trivial exceptions** (typo, one-line doc tweak) may go straight to `master`.
- **Docs-only PRs skip the install matrix, not the review** — `install-matrix.yml` sets
  `paths-ignore: ['docs/**', '**.md', 'claude/**/*.md']`, so a markdown-only change never
  triggers `linux`/`macos`/`windows`; don't wait for a run that will never start. review-stack still
  reviews every head of a non-draft PR, markdown included, so wait for its comment for the
  current head and triage the findings — `mergeStateStatus: CLEAN` also reads clean while
  the review hasn't posted yet. Markdown still has to pass R3 (no literal `/Users/<name>`
  paths outside `docs/**` and `HANDOFF.md`), which a markdown-only push never runs: write
  `/Users/<account>/`, `~` or `$HOME`.

Issue tracking: Linear, project `Dotfiles`, team `Villavicencio` (key `VIL`) —
https://linear.app/villavicencio/project/dotfiles-74974922348e (migrated off the
GitHub Projects board 2026-08-20; the board and closed GitHub issues are read-only
history — never create new GitHub issues).

- **PR review is review-stack, David's own reviewer** (since 2026-09-24, PRs #190 and
  later; replaces CodeRabbit here). It reviews every new head of an open, non-draft PR
  automatically, 2–6 minutes after the push, and posts one comment per head, starting with
  `<!-- review-stack:head=<full sha> run=<id> -->`. Wait for the comment for the current
  head (the `gh pr view … --jq` poll is in CLAUDE.md "Rules"), fix the real findings and push; the
  new head is re-reviewed automatically. Merge when the current head's review has no high or
  critical finding that is neither fixed nor waived with David. It doesn't read thread
  replies. Since MergeWren 0.4.0 each finding is also an inline thread: resolve it once
  fixed (listed under "Resolved") or declined. An incremental round can keep a finding
  "Still open" after the code it describes is gone; check it against the code and decline
  it as stale (`docs/reference/review-and-merge.md` has the #239 case). A `partial` verdict means a file wasn't
  reviewed, and so does "⚠️ The review did not complete": tell David. CodeRabbit comments are
  optional input: don't wait for them or re-trigger `@coderabbitai`.

---

## Install pipeline (what `./install` does)

Runs Dotbot with the platform config, which: (1) creates `~/.config/` dirs; (2) writes
`~/.zshenv` setting `ZDOTDIR=$HOME/.config/zsh`; (3) installs Oh My Zsh + plugins;
(4) symlinks config into `~/.config/`; (5) runs the `helpers/` scripts (omz, brew,
Brewfile, tmux, nvim, nvm, node). Each helper is independently runnable. (Nerd Fonts
install via Homebrew casks in `brew/Brewfile`, not a helper.)

**Windows:** `pwsh -File install.ps1 [-DryRun] [-SkipPackages]` instead — winget import
(`--no-upgrade`), symlinks for the configs shared with macOS (the Claude status line and
`nvim/` as `%LOCALAPPDATA%\nvim` included), stubs for `~/.gitconfig` and `$PROFILE`, a
`~/.claude/settings.json` seed (only when absent), the pre-commit hook, then the pinned nvim
plugins (`windows/install_nvim.ps1`). Full steps and rules: "Setting up the Windows PC" in
`docs/reference/windows.md`. Verify with a `-DryRun` (must report changes but make none) and a second real
run (every line must read `ok`). CI's `windows` job asserts both.

**Windows system settings:** from an elevated shell, preview with
`pwsh -File windows/tweaks.ps1 -DryRun`, then apply with `pwsh -File windows/tweaks.ps1`.
It's a separate opt-in step, because some entries need elevation and `install.ps1` stays
unelevated. It records only settings the PC already has and backs up prior values first.
The mouse and time entries also check the live session and apply live (mouse via
`SystemParametersInfo`; time via `w32tm /config /update` + `/resync`, run whenever the registry
or the service's reported source differs). Game Bar, Game Mode and GPU scheduling are plain registry writes and may need
a sign-out or restart. A `-DryRun` must read `ok` on every line, except Game Mode on a PC
that never toggled it: Windows defaults it on without writing `AutoGameModeEnabled`, so it
reads `would set` until the first real run. The Terminal default-profile entry picks the
`settings.json` of the running Terminal when both the packaged and unpackaged ones exist (and
fails naming both when it can't tell), edits only the top-level `defaultProfile` value found by
a comment-aware JSONC scan, and writes via a checked temp file. Before the swap it locks the
original against writes and renames (Terminal saves by renaming a temp file over it), re-checks
that it is unchanged since it was read, renames it aside through the lock, and renames the temp
file into place without replacing anything. Dot-source the script to test its functions
without running it. Details: "System tweaks" in `docs/reference/windows.md`.

### Server profile (`hal`)

`DOTFILES_PROFILE=server ./install` sets up `hal`, the headless Mac mini. It runs as the
standard account `hal` (no sudo; it owns Homebrew at `/opt/homebrew`), and `--dry-run`
previews it. In short:
- `base.yaml` runs with `--except clean`, then `server.yaml` runs in place of `darwin.yaml`.
- Packages come from `brew/Brewfile.server` (formulae plus allowlisted CLI-only casks), with
  no upgrades and no Homebrew bootstrap.
- No chsh, nvm/node/uv/Claude Code installers, Claude settings, `~/.claude` links, iTerm
  profile or nvim config.
- Three overlays get linked: `zsh/zprofile.server`, `git/gitconfig.server` and
  `tmux/local.server.conf`.

Verify with `ci/server-profile-checks.sh static`. The full write-up (layers, overlays,
`~/.zshenv` backup, CI's `macos-server` job) is in `docs/reference/install-and-server.md`.

## Invariants & gotchas (do not "fix" these)

- **`atlas`, `axiom` and `syd` (`zsh/functions/`) decide when sourced whether to exist.** `syd`
  (`hermes -p syd --tui "$@"`) is defined only where `~/.hermes/profiles/syd` exists, which is
  the personal Mac. All three drop their function when a Hermes wrapper of the same name is in
  `~/.local/bin`. `atlas` and `axiom` share `_hal_console` (`hal_console.sh`), which keys on a
  local `hal` account, not on `orca` being on PATH (#229). Usage is in `README.md` ("Hermes agents"), and the details are in
  `docs/reference/hermes-commands.md`.

- **No heredocs in `bin/dot` — do not inline `bin/lib/*.py` back into `python3 - <<'PY'`.**
  Bash backs a small heredoc with a pipe and writes the *whole* document before forking the
  reader, so a blocked write never clears: the process that would drain the pipe does not
  exist yet. This deadlocked `dot doctor` in ~1 of 8 runs (hung in the first check, no child
  process, no output). Counter-intuitively **small heredocs are the risky ones** — bash uses a
  temp file for large ones. Use a real file, or `< <(printf …)` for variable payloads. Write-up:
  `docs/solutions/runtime-errors/dot-doctor-heredoc-pipe-deadlock-2026-08-07.md`.
- **Tool-managed shell-rc blocks** — some blocks in the shell rc files are managed
  by their own tools and must not be reformatted or absorbed into repo conventions.
- **sudo does not work from an agent shell without Touch ID.** Claude Code's `!` mode and
  Bash tool have no controlling TTY, so any `sudo` fails with "a terminal is required."
  The fix is a one-time root step creating `/etc/pam.d/sudo_local` with `pam_reattach`
  (tmux) + `pam_tid` — documented in `docs/reference/tooling.md` under "Touch ID for sudo"; it cannot be
  Dotbot-managed because `/etc/pam.d/` is root-owned and outside `$HOME`.
  Do **not** substitute `SUDO_ASKPASS` (plain `sudo` ignores it — only `sudo -A` consults
  it), `sudo -v` pre-caching (`tty_tickets` keys the cache to the originating terminal), or
  a NOPASSWD sudoers entry (cask scripts run arbitrary `sudo rm -rf`; that is passwordless
  root). Note `topgrade --dry-run | grep sudo` does not predict which steps need root — a
  cask's own script can invoke sudo internally. Full write-up:
  `docs/solutions/security/sudo-in-no-tty-agent-shells-touch-id-2026-08-07.md`.
- **herdr is retired (2026-10-22, VIL-422).** Orca hosts the agent sessions now. What was
  removed and the lessons that outlive it:
  `docs/solutions/integration-issues/herdr-agent-fleet-retired-2026-10-22.md`.
- **`claude/settings.json` is copy-seeded — do not add a `link:` entry for it.**
  Writers besides this repo rewrite `~/.claude/settings.json` in place: Claude Code
  itself and agent-integration installers (Orca's agent hooks today; herdr's until
  2026-10-22, Otty's until 2026-09-03). A symlink is orphaned on the first write. This already bit once — the repo copy sat
  stale from 2026-08-07 to 2026-08-25 while the live file regrew a legacy top-level
  `allowedTools` key (18 rules) against a `permissions.allow` of 1, silently re-arming the
  precedence trap PR #127 had removed: when both keys exist the legacy one WINS and
  `permissions.allow` is inert. `helpers/install_claude_settings.sh` seeds when absent and
  `--capture` records live changes back (dropping the machine-local keys `effortLevel`,
  `modelSettings`, `autoMode`, `mcpServers`, `allowedTools`, and normalizing `$HOME` paths to `~/`).
  `dot drift` compares capture-normalized forms and warns if `allowedTools` reappears.
  Agents cannot write this file — the auto-mode classifier blocks it by design; run
  `helpers/migrate_claude_settings.py` yourself on a machine that predates the scheme (on
  Windows, run it as `python` under Git Bash).
- **`git/gitconfig` `core.pager = vim -`** is intentional on the Macs; `diff`/`show` route
  through **delta** via the `[pager]` overrides. Linux gets `less -FRX` from the overlay below.
- **Linux git config is `git/gitconfig` plus an overlay, via an include, not a stub.**
  `git/gitconfig` `[include]`s `~/.config/git/gitconfig.platform` after its `[credential]`
  sections and before `~/.gitconfig.local`. `linux.yaml` links that path to
  `git/gitconfig.linux`; macOS links nothing, and git skips a missing include, so the Macs
  resolve the same config as before. The overlay resets the multi-valued
  `credential.helper` lists with an empty value (dropping `osxkeychain`, the `/usr/local`
  GCM path and `/opt/homebrew/bin/gh`), then adds `!/usr/bin/gh auth git-credential` for
  github.com/gist.github.com only. So `git config --get-all credential.helper` still
  *prints* the macOS values on Linux; check what git actually runs with
  `GIT_TRACE=1 git credential fill`, as CI's R8 assertion does. Not `includeIf "gitdir:…"`:
  every includeIf condition is about the repo, none about the OS. `git-delta`, `vim` and
  `less` are in the Linux apt list because the git config names them (VIL-146).
- **Agent SSH sessions can't read the macOS keychain** ("User interaction is not allowed"), so
  anything stored there reads as logged out over `ssh mac`: `gh` reports "The token in default is
  invalid" and Codex MCP logins show "Not logged in". On the personal Mac both use file storage
  instead (2026-09-30): `gh` via `gh auth token | gh auth login -h github.com --with-token
  --insecure-storage` (token in `~/.config/gh/hosts.yml`, mode 600), Codex via
  `mcp_oauth_credentials_store = "file"` in `~/.codex/config.toml` followed by a fresh
  `codex mcp login <server>`. Check with `gh auth status` and `codex mcp list` over SSH.
- **GCM credential-helper entries** in `git/gitconfig` are auto-generated — commit them
  separately from other work.
- **`MYSQL_BIN="/usr/local/mysql/bin"`** is the MySQL PKG installer path on both
  architectures — not a Homebrew path, do not `$BREW_PREFIX` it.
- **Linux Dotbot config + `uname` guards** outlived the VPS and are in use again for WSL
  Ubuntu. Two WSL-found invariants: zsh is installed in `base.yaml`'s Linux locale step
  (Oh My Zsh runs first and needs it; CI's image pre-installs it, masking this), and any
  Dotbot shell step that prompts — `linux.yaml`'s `chsh` — needs `stdin: true` (Dotbot
  defaults stdin to `/dev/null`). Write-up:
  `docs/solutions/cross-machine/wsl-ubuntu-target-2026-09-24.md`.
- **nvim pins: the first launch on an empty machine drifts them.** lazy.nvim installs in
  rounds, and the lockfile write between rounds drops NvChad-imported plugins, which then
  land at their branch HEAD and are written back into the tracked `nvim/lazy-lock.json`
  (through the link). `helpers/install_nvim.sh` and `windows/install_nvim.ps1` keep a
  copy of the pins, put it back, restore, and verify against the copy with
  `helpers/nvim_verify_lock.lua`. Don't reduce this to one `Lazy! restore`. Before taking
  the pin snapshot or launching nvim, both helpers fail (exit 1, config dir untouched)
  unless nvim's config dir resolves to this repo's `nvim/`, since an existing real
  `~/.config/nvim` or `%LOCALAPPDATA%\nvim` stays in place when it can't be linked over.
  The Neovim install/upgrade checks run earlier, and `-AllowMissing` exits 0 before the
  guard. The minimum is
  Neovim **0.12** (the pinned nvim-treesitter needs it). An older installed nvim is
  upgraded (brew/winget), and the helper fails if it is still too old rather than skipping. On Linux the helper installs the
  pinned release tarball into `~/.local` (no sudo; apt's 0.9.5 is not used). Write-up:
  `docs/solutions/runtime-errors/lazy-nvim-first-launch-drifts-lockfile-2026-09-24.md`.
- **Windows gets stubs, not links, for `~/.gitconfig` and `$PROFILE`** — git has no
  OS-conditional include, and `$PROFILE` sits under a OneDrive-redirected Documents folder.
  **Windows seeds `windows/claude-settings.json`, never `claude/settings.json`** (the Mac
  file's hooks are tmux bash scripts that would error on every event). The Windows
  file is the Mac baseline minus `hooks`, `preferredNotifChannel`, and the brew/tmux allow
  rules; the `statusLine` block is identical and runs under Git Bash's `sh`. Keep the two
  files' shared keys in step by hand. Same copy-only-when-absent contract, and the
  helpers (`install_claude_settings.sh --capture`, `report_drift.sh`) switch to the
  Windows file under Git Bash so a capture on the PC can't overwrite the Mac baseline.
  On Windows `report_drift.sh` skips the Homebrew/npm inventories (Mac/Linux manifests)
  and runs only the Claude comparison, with a Python probe that rejects the Microsoft
  Store `python3` placeholder. With no working Python, both helpers run one through
  `uv run --no-project --quiet python` (install.ps1 installs uv, not Python); with neither
  they fail loudly. Python is resolved lazily, only when settings are actually compared or
  captured, so other runs never probe or let uv download. A failed normalization is an error, never "(in sync)".
  **Don't link `topgrade/topgrade.toml` there** (its `[commands]` entry is POSIX shell).
  Write-up: `docs/solutions/cross-machine/windows-target-gotchas-2026-09-24.md`.
- The **tmux session-restoration block** in `zshrc` is guarded to run only outside tmux and
  only in iTerm2.

Deeper write-ups for past bugs and decisions live in `docs/solutions/` (grouped by
category, indexed in `docs/solutions/INDEX.md`), and the per-area reference (Windows, WSL,
the server profile, Claude Code config, Orca worktrees, review) in `docs/reference/`.
Consult them before re-deriving a fix.
