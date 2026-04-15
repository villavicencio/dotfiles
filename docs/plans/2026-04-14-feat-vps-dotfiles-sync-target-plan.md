---
title: Make VPS a first-class dotfiles sync target
type: feat
status: active
date: 2026-04-14
origin: docs/brainstorms/2026-04-14-vps-dotfiles-target-brainstorm.md
---

# Make VPS a first-class dotfiles sync target

## Overview

Promote the OpenClaw VPS (`root@openclaw-prod`, Ubuntu 24.04, Hetzner,
Tailscale-only, Coolify-managed Docker host) from an ad-hoc clone of this
repo into a first-class dotfiles sync target alongside `personal` and `work`
Macs. Deliver three things together:

1. A Linux install profile that ships shell + tmux parity to the VPS and
   skips Mac-only ceremony (Homebrew, fonts, iTerm, osx defaults, chsh).
2. A human-gated GitHub Actions workflow that syncs the VPS on demand via an
   ephemeral tailnet node, with a baked-in health check and git-reset
   rollback on failure.
3. Documentation, runbook, and acceptance tests that make the operation
   repeatable for a second Linux host and auditable after drift.

**Non-goals (deferred):** fixing `zsh/alias.sh` Mac-unguarded aliases; Claude
Code parity on VPS; non-root user on Linux; non-Debian distros.

## Problem Statement

### Today's state (observed this session)

- VPS `/root/.dotfiles` was **50 commits behind** master before we caught it.
  No mechanism prevents silent drift.
- Two local-only modifications existed in the VPS clone:
  `git/gitconfig` had `[safe]` entries for Docker volumes, and `tmux/tmux.conf`
  forward-ported the `local.conf` include that later landed in commit
  `a8a41e6`. The `[safe]` entries have been moved into `~/.gitconfig.local`
  this session; the tmux.conf merge is now clean.
- `./install` hardcodes `install.conf.yaml` and invokes Mac-only helpers
  (`chsh`, `install_fonts.sh`, `install_nvm.sh`, `install_node.sh`) that are
  wrong or wasted on the VPS.
- The recent OSC 52 / `set-clipboard on` work exposed the cost of drift:
  testing end-to-end required editing the VPS live instead of syncing
  through the repo.

### What we need

- Zero-risk change to the Mac install path (personal + work must behave
  identically before and after).
- Zero-risk change to production services on the VPS (Docker volumes,
  Coolify-managed services, Forge agents, OpenClaw gateway untouched).
- A repeatable way to land dotfile updates on the VPS without hand-editing.
- A safety posture that catches regressions *during* the sync, not hours
  later via `/pickup` Step 2d.

## Proposed Solution

Three coordinated changes:

### A. Wrap `./install` with OS detection

Replace the literal `CONFIG="install.conf.yaml"` in the entry script with a
`uname`-driven case. Mac path unchanged (same `install.conf.yaml`); Linux
path routes to a new sibling `install-linux.conf.yaml`.

Also: pass `--dry-run` through to Dotbot (vendored at v1.24.1, which
supports native dry-run — see commit `6a449ea` for the submodule bump)
and export `DOTFILES_DRY_RUN=1` as defense-in-depth for any helper
invoked directly outside Dotbot. Dotbot's native dry-run covers every
built-in directive (`link`, `create`, `clean`, `shell`) and emits
"Would create path / Would create symlink / Would run command" preview
lines — no filesystem mutation, even on a fresh host.

*Note: the original design relied on the wrapper stripping `--dry-run`
and helpers honoring `DOTFILES_DRY_RUN`. During review a reviewer
reproduced that on a fresh `HOME`, Dotbot's built-in link/create/clean
still mutated the filesystem because the vendored v1.19.0+17 didn't
support native dry-run. The design was corrected by bumping Dotbot.
The env-var mechanism is retained for direct-invocation scenarios and
for the inline `shell:` blocks that benefit from emitting a
human-readable `[dry-run] would ...` message.*

### B. Author a Linux-only Dotbot config

`install-linux.conf.yaml` mirrors the Mac config's structure but:

- Drops `~/.claude/*` create + link directives (no Claude Code on VPS).
- Drops `~/.local/share/fonts` create + `install_fonts.sh` shell.
- Drops `install_nvm.sh` + `install_node.sh` shells (Docker has its own Node).
- Drops `chsh -s $(which zsh)` (root's default shell is already
  `/usr/bin/zsh` on this VPS — verified).
- Keeps: zsh/git/tmux/btop/lazygit/topgrade links,
  `nvim/lua/custom` link, `install_omz.sh`, `install_packages.sh` (apt
  branch — Ubuntu 24.04 confirmed),
  `install_tmux.sh` (TPM — safe on Linux, Homebrew init is already
  guarded behind `uname = Darwin`), `install_nvim.sh` (NvChad base).
- Adds a pre-shell step: `[ -f ~/.gitconfig.local ] || touch ~/.gitconfig.local`
  so git never errors on the `[include]` directive (addresses SpecFlow #8).

### C. GitHub Actions workflow with Tailscale transport

`.github/workflows/sync-vps.yml` — manual-only (`workflow_dispatch`),
Tailscale `@v4` ephemeral runner, single-job pipeline: snapshot pre-install
SHA → pull → install → health check (retried) → rollback on failure via
`git reset --hard <prev-sha> && ./install`. `concurrency: sync-vps` prevents
reentrant runs. Job- and step-level `timeout-minutes` guard against hangs.

**Transport details** (from research):

- Tailscale GH Action `@v4` (not `@v2`; v2 is legacy).
- OAuth client with `auth_keys:write` scope, tagged `tag:gh-actions`.
- VPS tagged `tag:prod` in Tailscale admin.
- ACL `ssh` block grants `tag:gh-actions` → `tag:prod` — no SSH private key
  needed. Tailscale SSH authenticates by tailnet identity.
- `ping: openclaw-prod` input waits for propagation before SSH attempts.

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Developer Mac (personal / work)                                 │
│   $ ./install              → install.conf.yaml   (unchanged)    │
│   $ ./install --dry-run    → same, dry                          │
└────────────────────────────┬────────────────────────────────────┘
                             │ git push origin master
                             ▼
                       github.com/villavicencio/dotfiles
                             │
                             │ workflow_dispatch (manual)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ GitHub Actions (ubuntu-latest, ephemeral)                       │
│   - tailscale/github-action@v4  (joins tailnet as gh-actions)   │
│   - ping: openclaw-prod          (wait for propagation)         │
│   - record pre-install SHA       (step output)                  │
│   - ssh root@openclaw-prod                                      │
│       (tailnet identity, no SSH key)                            │
│         cd /root/.dotfiles                                      │
│         git fetch && git reset --hard origin/master             │
│         ./install [--dry-run]                                   │
│   - health check (retried 3x, 10s gap)                          │
│       • docker ps --format ... | grep -c ^openclaw- (>= 1)      │
│       • openclaw status --deep (no CRITICAL/ERROR)              │
│       • zsh -i -c exit (interactive shell sane)                 │
│   - rollback on health failure:                                 │
│       git reset --hard <prev_sha> && ./install                  │
└─────────────────────────────────────────────────────────────────┘
                             │
                             ▼
                     VPS `openclaw-prod`
                     (Docker host, containers untouched)
```

### File changes

| Path | Change | Notes |
|---|---|---|
| `install` | Modify | OS-detect case; pass `--dry-run` through to Dotbot (v1.24.1 supports it natively); also export `DOTFILES_DRY_RUN=1` as defense-in-depth for direct helper invocation |
| `dotbot/` (submodule) | Bump | v1.19.0+17 → v1.24.1 for native `--dry-run` support |
| `install-linux.conf.yaml` | **New** | Linux profile — trimmed, bracket-shorthand for shell steps |
| `helpers/install_packages.sh` | Modify | Single `DOTFILES_DRY_RUN` guard at top of Linux branch; keep existing apt-get -y install block (already idempotent) |
| `helpers/install_omz.sh` | Modify | `DOTFILES_DRY_RUN` fork (it does `git clone` today) |
| `helpers/install_tmux.sh` | Modify | `DOTFILES_DRY_RUN` fork (TPM clone + plugin install) |
| `helpers/install_nvim.sh` | Modify | `DOTFILES_DRY_RUN` fork (NvChad clone) |
| `scripts/post-deploy-smoke.sh` | **New** | Shellcheck-able smoke test; invoked by workflow and available for manual runs |
| `.github/workflows/sync-vps.yml` | **New** | Manual sync workflow (`workflow_dispatch` only, Tailscale transport) |
| `docs/solutions/cross-machine/vps-dotfiles-target.md` | **New** | Single consolidated doc: bootstrap, Tailscale OAuth + ACL setup, verification runbook, rollback drill, rotation |
| `CLAUDE.md` | Modify | Add VPS row (`vps \| Ubuntu 24.04 \| Hetzner VPS \| OpenClaw + Forge host`); add "Setting up a Linux host" section; document `DOTFILES_DRY_RUN` under Key Conventions; note that `tag:prod` auto-grants GH-Actions root SSH |
| `README.md` | Modify (if exists) | Link to VPS setup docs |

**No modifications** to: `zsh/*`, `tmux/*`, `git/gitconfig`, `install.conf.yaml`, any helper not listed above. Mac install path is literally unchanged.

### Implementation checklist (single PR)

The work below is one PR, not three phases. Decomposing into phases would
create a merge state where the OS-detecting wrapper was live but the
workflow wasn't — no value, more ceremony. Keep the ordering below as an
internal implementation order to work through and gate progress.

#### 1. Local (Mac-side) plumbing — no VPS contact

**Deliverables:**
- Modified `install` wrapper (OS-detect + dry-run env var).
- New `install-linux.conf.yaml`.
- Modified helpers with `DOTFILES_DRY_RUN` forks.
- New `scripts/post-deploy-smoke.sh`.
- Local verification that Mac path is unaffected.

**Success criteria:**
- `./install --dry-run` on personal Mac produces the identical symlink-plan
  output as before (except for the "would link" labels); no filesystem
  mutations observed via `ls -la ~ ~/.config/*` diff.
- `./install` on personal Mac is a no-op (all links present, no errors).
- `bash -n install install-linux.conf.yaml scripts/post-deploy-smoke.sh`
  and `shellcheck install scripts/post-deploy-smoke.sh helpers/install_packages.sh`
  both pass.
- Dotbot accepts `install-linux.conf.yaml` via
  `./dotbot/bin/dotbot -d . -c install-linux.conf.yaml --dry-run` run
  locally (will fail on some create: dirs because `~/.config/tmux` etc.
  already exist and aren't directories, that's fine — we want to confirm
  the YAML parses and Dotbot enumerates the right targets).

**Specifically — the new `install` wrapper** (complete, replaces current file):

```bash
#!/usr/bin/env bash
set -e

DOTBOT_DIR="dotbot"
DOTBOT_BIN="bin/dotbot"
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname)" in
  Darwin) CONFIG="install.conf.yaml" ;;
  Linux)  CONFIG="install-linux.conf.yaml" ;;
  *)      echo "Unsupported OS: $(uname)" >&2; exit 1 ;;
esac

# --dry-run is a genuine preview with vendored Dotbot >= v1.23.0:
# - link / create / clean / shell plugins all support dry-run natively
#   (they print what they would do without mutating)
# - pass the flag through so Dotbot handles preview for every directive
# Also export DOTFILES_DRY_RUN=1 as defense-in-depth for any helper invoked
# directly (outside Dotbot) and for inline shell blocks that want to emit a
# human-readable "[dry-run] would ..." message.
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; then
    export DOTFILES_DRY_RUN=1
    break
  fi
done

cd "${BASEDIR}"
git -C "${DOTBOT_DIR}" submodule sync --quiet --recursive
git submodule update --init --recursive "${DOTBOT_DIR}"

exec "${BASEDIR}/${DOTBOT_DIR}/${DOTBOT_BIN}" -d "${BASEDIR}" -c "${CONFIG}" "$@"
```

**Specifically — `install-linux.conf.yaml` skeleton** (mirrors `install.conf.yaml`
shape including the bracket-shorthand for shell steps and `quiet: true` defaults).
The `touch ~/.gitconfig.local` step the brainstorm proposed is removed — git's
`[include] path` silently ignores missing files, so it was cargo-cult safety:

```yaml
- defaults:
    link:
      relink: true
    shell:
      quiet: true
      stdout: true
      stderr: true

- clean: ['~']

- create:
    - ~/.hushlogin
    - ~/.config
    - ~/.config/zsh
    - ~/.config/btop
    - ~/.config/git
    - ~/.config/lazygit
    - ~/.config/tmux
    - ~/.config/tmux/resurrect
    - ~/.config/tmux/plugins
    - ~/.config/tmux/scripts

- shell:
    - [grep -q 'ZDOTDIR' ~/.zshenv 2>/dev/null || echo 'export ZDOTDIR=$HOME/.config/zsh' > ~/.zshenv, Setting ZDOTDIR in .zshenv]
    - ["command -v locale-gen >/dev/null 2>&1 && sudo locale-gen en_US.UTF-8 || true", "Generating en_US.UTF-8 locale"]
    - [grep -q '. ~/.config/zsh/.zshenv' ~/.zshenv 2>/dev/null || echo '. ~/.config/zsh/.zshenv' >> ~/.zshenv, "Adding dot command for more extensive zshenv in .zshenv"]
    - [bash helpers/install_omz.sh, "Installing omz + plugins"]

- link:
    ~/.config/zsh/.zshenv: zsh/zshenv
    ~/.config/zsh/.zshrc:  zsh/zshrc
    ~/.gitconfig:          git/gitconfig
    ~/.config/git/gitignore:    git/gitignore
    ~/.config/git/gitattributes: git/gitattributes
    ~/.config/btop/btop.conf:   btop/btop.conf
    ~/.config/lazygit/config.yml: lazygit/config.yml
    ~/.config/tmux/tmux.conf:   tmux/tmux.conf
    ~/.config/topgrade.toml:    topgrade/topgrade.toml

- shell:
    - [. ~/.zshenv, "Source .zshenv"]
    - [git submodule update --init --recursive, "Installing submodules"]
    - [bash helpers/install_packages.sh, "Installing packages"]
    - [bash helpers/install_tmux.sh, "Installing tmux + plugins"]
    - [bash helpers/install_nvim.sh, "Installing nvim + plugins"]

- link:
    ~/.config/tmux/scripts/save-window-meta.sh: tmux/scripts/save-window-meta.sh
    ~/.config/tmux/scripts/restore-window-meta.sh: tmux/scripts/restore-window-meta.sh
    ~/.config/nvim/lua/custom: nvim/custom
```

Note on locale-gen: removed the explicit `[ "$(uname)" != Darwin ]` guard
because this file ONLY runs on Linux (enforced by the wrapper). Simpler.

**Specifically — `install_packages.sh` change** (apt branch only, Darwin
branch unchanged). Simpler than the brainstorm draft: `apt-get install -y` is
idempotent on Ubuntu 24.04 (returns 0 when pkg is already at newest version),
the package list is small and curated, and one bad package halting the batch is
a paper risk not worth 20 lines of guard code. Single dry-run guard at the top
of the Linux branch:

```bash
# Linux (apt) branch — preserve existing structure, add one guard.
if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would run apt-get update + install curated package list"
  exit 0
fi

sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq

# Single install command (unchanged from today's helper).
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  bat btop curl fd-find fzf gawk git jq \
  ncdu neovim ripgrep shellcheck tig tmux \
  tree watch wget zsh build-essential cmake \
  luarocks python3-pip pipx

# Existing gh, starship, diff-so-fancy, fd/bat symlink blocks stay (they
# already have command -v guards). diff-so-fancy block silently no-ops
# when npm is absent — per scope, NVM/Node are not installed on VPS.
```

**What we dropped vs. the brainstorm draft and why:**
- Per-package loop with `command -v` guards: `apt-get install -y` is already
  idempotent, list is curated and stable.
- `declare -A BIN_FOR` associative array: only needed if we had the loop.
- `::warning::` GitHub-Actions annotation in a general-purpose helper: leaks
  CI concerns into a helper that also runs on bare dev laptops. If a package
  fails, the workflow's own log already surfaces it.
- Per-package fail-loud-continue: if the curated list gains a drifted
  package, fix the list in a PR. Don't build generic error recovery for a
  hypothetical failure mode.

**Helpers that clone** (omz, tmux/TPM, nvim/NvChad) each get the same
front-matter:

```bash
if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install Oh My Zsh + plugins"
  exit 0
fi
```

#### 2. GitHub Actions workflow + Tailscale setup

**Deliverables:**
- `.github/workflows/sync-vps.yml`.
- Tailscale admin: OAuth client, `tag:gh-actions` + `tag:prod` tagOwners,
  ACL `ssh` block.
- GitHub repo secrets: `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`.
- VPS: tag applied via `tailscale up --advertise-tags=tag:prod` (or admin
  console edit).
- Tailscale OAuth / ACL setup documented as a subsection of the
  consolidated `docs/solutions/cross-machine/vps-dotfiles-target.md` runbook
  (see step 3 below for the full doc outline).

**Success criteria:**
- `tailscale ssh root@openclaw-prod echo ok` from the user's Mac prints
  `ok` (validates ACL + tag before any workflow run — SpecFlow #5).
- `gh workflow run sync-vps.yml -f dry_run=true` completes green and its
  logs show "would link" entries without mutating VPS filesystem.
- Second invocation (`dry_run=false`) lands changes and passes the health
  check retries.

**Workflow file** (`.github/workflows/sync-vps.yml`) — updated shape:

```yaml
name: Sync VPS
run-name: "Sync VPS (${{ inputs.dry_run && 'dry-run' || 'apply' }}) by @${{ github.actor }}"

on:
  workflow_dispatch:
    inputs:
      host:
        description: 'Target host (defaults to openclaw-prod)'
        type: string
        default: openclaw-prod
        required: true
      dry_run:
        description: 'Preview only (no filesystem changes on VPS)'
        type: boolean
        default: true
        required: true

# Queue behind an in-flight run on the same host; allow parallel runs against
# different hosts if/when a second Linux target joins.
concurrency:
  group: sync-vps-${{ inputs.host }}
  cancel-in-progress: false

jobs:
  sync:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - name: Tailscale
        uses: tailscale/github-action@v4
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret:    ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:gh-actions
          version: latest
          ping: ${{ inputs.host }}

      - name: Record pre-install SHA
        id: snapshot
        timeout-minutes: 2
        run: |
          SHA=$(ssh -o StrictHostKeyChecking=accept-new "root@${{ inputs.host }}" \
            'cd /root/.dotfiles && git rev-parse HEAD')
          # Kill the SSH-injection bug class: the value is interpolated into a
          # remote shell in the rollback step. Must be exactly a 40-char hex SHA.
          [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid SHA: '$SHA'" >&2; exit 1; }
          echo "prev_sha=$SHA" >> "$GITHUB_OUTPUT"
          echo "### Pre-install SHA" >> "$GITHUB_STEP_SUMMARY"
          echo "\`$SHA\`" >> "$GITHUB_STEP_SUMMARY"

      - name: Fetch latest
        timeout-minutes: 3
        run: |
          ssh "root@${{ inputs.host }}" \
            'cd /root/.dotfiles && git fetch && git reset --hard origin/master'

      - name: Install
        id: install
        timeout-minutes: 8
        continue-on-error: true
        run: |
          DRY="${{ inputs.dry_run && '--dry-run' || '' }}"
          ssh "root@${{ inputs.host }}" \
            "cd /root/.dotfiles && ./install $DRY"

      - name: Health check
        id: healthcheck
        if: ${{ !inputs.dry_run }}
        timeout-minutes: 5
        continue-on-error: true
        run: |
          # scripts/post-deploy-smoke.sh lives in THIS repo and is SCPed over,
          # or (simpler) checked into /root/.dotfiles/scripts/ so it was already
          # pulled in the "Fetch latest" step.
          ssh "root@${{ inputs.host }}" \
            'bash /root/.dotfiles/scripts/post-deploy-smoke.sh'

      - name: Publish status summary
        if: ${{ always() }}
        run: |
          {
            echo "### Sync run summary"
            echo ""
            echo "| Field | Value |"
            echo "| --- | --- |"
            echo "| Host | \`${{ inputs.host }}\` |"
            echo "| Mode | ${{ inputs.dry_run && 'dry-run' || 'apply' }} |"
            echo "| Pre-SHA | \`${{ steps.snapshot.outputs.prev_sha }}\` |"
            echo "| Install outcome | ${{ steps.install.outcome }} |"
            echo "| Health outcome | ${{ steps.healthcheck.outcome }} |"
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Rollback on failure
        id: rollback
        if: ${{ always() && !inputs.dry_run && (steps.install.outcome == 'failure' || steps.healthcheck.outcome == 'failure') }}
        timeout-minutes: 5
        run: |
          PREV="${{ steps.snapshot.outputs.prev_sha }}"
          if [ -z "$PREV" ]; then
            echo "::error::no prev SHA captured — manual intervention required"
            exit 1
          fi
          # Remote-side preflight: confirm the commit exists locally and differs
          # from HEAD before resetting.
          ssh "root@${{ inputs.host }}" "
            set -e
            cd /root/.dotfiles
            CUR=\$(git rev-parse HEAD)
            if [ \"\$CUR\" = \"$PREV\" ]; then
              echo '::error::rollback target equals current HEAD — nothing to roll back to'
              exit 1
            fi
            git rev-parse '$PREV^{commit}' >/dev/null 2>&1 || {
              echo '::error::prev SHA not found in local git log — manual intervention required'
              exit 1
            }
            git reset --hard $PREV
            ./install
          "
          echo "### Rollback" >> "$GITHUB_STEP_SUMMARY"
          echo "Reset VPS to \`$PREV\` and re-ran install." >> "$GITHUB_STEP_SUMMARY"
          # Exit 1 so the workflow run is marked failed — a rollback IS a deploy
          # failure even if it succeeded mechanically.
          exit 1
```

Notes:
- `continue-on-error: true` on the `Install` step lets the `Rollback` step
  fire on install failure (not just health-check failure). The SpecFlow
  gap from the prior draft (install failure → healthcheck skipped → rollback
  skipped) is closed by widening the rollback condition to cover both.
- `concurrency.group` is parameterized by host so future targets don't
  share a queue.
- No separate "Fail workflow if health check failed" belt-and-suspenders
  step — rollback's `exit 1` is the single failure gate.

**Smoke-test script** (`scripts/post-deploy-smoke.sh`, runs on VPS after pull):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Exponential backoff with jitter — retry ONLY transient checks.
# Permanent failures (container absent, shell broken) fail fast.

# 1. Permanent check: at least one openclaw-* container running.
#    `^openclaw-` prefix match survives Coolify UUID rotation.
running=$(docker ps --format '{{.Names}}' | grep -c '^openclaw-' || true)
[ "$running" -ge 1 ] || { echo "FAIL: no openclaw-* container running"; exit 1; }

# 2. Permanent check: interactive zsh inits cleanly (catches zshrc regressions
#    like a bad PATH or a syntax error in a sourced file).
zsh -i -c exit || { echo "FAIL: zsh -i -c exit non-zero"; exit 1; }

# 3. Transient check: openclaw status --deep reports no CRITICAL/ERROR.
#    Retry up to 3 times with exponential backoff + small jitter — tolerates
#    brief CRITICAL during container restart.
CID=$(docker ps --filter name=openclaw- -q | head -1)
[ -n "$CID" ] || { echo "FAIL: docker ps filter returned no CID"; exit 1; }

attempt=1
max_attempts=3
while : ; do
  bad=$(docker exec "$CID" openclaw status --deep 2>&1 | grep -cE '^(CRITICAL|ERROR)' || true)
  [ "$bad" = "0" ] && break
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "FAIL: openclaw status dirty after $max_attempts attempts (last: $bad bad lines)"
    exit 1
  fi
  # sleep ~ 2^attempt + jitter(0..2), capped at 10s
  delay=$(( (1 << attempt) + RANDOM % 3 ))
  [ "$delay" -gt 10 ] && delay=10
  sleep "$delay"
  attempt=$((attempt + 1))
done

# 4. Optional host-specific hook.
if [ -x "$HOME/.dotfiles-healthcheck.sh" ]; then
  "$HOME/.dotfiles-healthcheck.sh" || { echo "FAIL: host-specific healthcheck"; exit 1; }
fi

echo "OK: all post-deploy checks passed"
```

The optional `~/.dotfiles-healthcheck.sh` is the pluggable seam (architecture
review finding #1). Today it doesn't exist on the VPS; the generic checks are
sufficient. If a second Linux host ever joins that needs different
assertions, it drops a script at that path.

#### 3. Docs + runbook + CLAUDE.md updates

**Deliverables:**
- `docs/solutions/cross-machine/vps-dotfiles-target.md` — single consolidated doc with frontmatter matching the existing `cross-machine/` schema (title/date/category/tags/component/status). Sections:
  - Bootstrap (fresh Ubuntu host): `apt-get install git zsh && git clone
    ... && cd ~/.dotfiles && ./install --dry-run && ./install`.
  - Machine-local overrides: `~/env.sh` (optional, empty template),
    `~/.gitconfig.local` (required for Docker-volume `safe.directory`
    entries — show full content and note the security trade-off).
  - **Tailscale OAuth + ACL setup** (subsection): OAuth client creation,
    tagOwners + ssh ACL JSON diff, GitHub secret upload, first-time smoke
    test (`tailscale ssh root@openclaw-prod echo ok`), rotation runbook,
    Configuration Audit Log reference
    (https://login.tailscale.com/admin/logs).
  - **Pre-deploy Go/No-Go checklist** — non-shallow repo check, clean
    working tree check, baseline snapshot capture.
  - **Rollback drill procedure** — how to validate the rollback path with
    a harmless commit before relying on it in anger.
  - **Verification runbook** — the five paste-able commands.
  - **Tailscale-down fallback** — mosh via `tailscale ip -4 openclaw-prod`.
  - **Annual reminder**: Forge ticket due 2027-04-14 to rotate OAuth
    client secret (delete old client first, then create new).
- `CLAUDE.md` updates:
  - Add VPS row to machine table:
    `vps | Ubuntu 24.04 | Hetzner VPS | OpenClaw + Forge host`.
  - Add "Setting up a Linux host (VPS)" section mirroring the work-Mac
    section's style.
  - Under "Key conventions," document `DOTFILES_DRY_RUN=1` as a first-class
    env-var contract honored by helpers.
  - Add a one-line guardrail under "Things intentionally left as-is":
    `tag:prod` in Tailscale auto-grants root SSH from `tag:gh-actions`
    — do not apply `tag:prod` to a node without reviewing the ACL.

**Verification commands** (from SpecFlow #10, baked into PR description and
the VPS runbook):

```bash
# 1. Symlinks landed, point into repo
tailscale ssh root@openclaw-prod 'readlink ~/.config/zsh/.zshrc' \
  | grep -q '/root/.dotfiles/zsh/zshrc' && echo "OK: zshrc symlink"

# 2. Interactive zsh loads without error
tailscale ssh root@openclaw-prod 'zsh -i -c "echo OK"' | grep -q OK \
  && echo "OK: interactive zsh"

# 3. Git repo matches remote master
LOCAL=$(tailscale ssh root@openclaw-prod 'cd /root/.dotfiles && git rev-parse HEAD')
REMOTE=$(git ls-remote origin master | awk '{print $1}')
[ "$LOCAL" = "$REMOTE" ] && echo "OK: git in sync ($LOCAL)"

# 4. OpenClaw container still running
COUNT=$(tailscale ssh root@openclaw-prod \
  'docker ps --format "{{.Names}}" | grep -c "^openclaw-"')
[ "$COUNT" -ge 1 ] && echo "OK: $COUNT openclaw-* container(s) running"

# 5. Deep status clean. Guard against empty-CID crash.
BAD=$(tailscale ssh root@openclaw-prod '
  CID=$(docker ps --filter name=openclaw- -q | head -1)
  [ -n "$CID" ] || { echo "NO_CONTAINER"; exit 0; }
  docker exec "$CID" openclaw status --deep 2>&1
' | grep -cE '^(CRITICAL|ERROR)' || true)
[ "$BAD" = "0" ] && echo "OK: deep status clean"
```

**Known gap:** command 2 (`zsh -i -c "echo OK"`) catches shell-init
regressions on new sessions but does NOT detect a broken `tmux.conf`
affecting *already-attached* tmux sessions. After a deploy that touched
`tmux/tmux.conf`, manually verify by re-sourcing in an attached session:
`tmux source-file ~/.config/tmux/tmux.conf` and confirm no error banner.

## Alternative Approaches Considered

### 1. Separate `./install-linux` entry script

Rejected during brainstorm (Q: Install shape). Having users remember
different entry commands per host is friction; `uname` is more reliable
than human memory.

### 2. Single `install.conf.yaml` with Dotbot `if:` conditionals

Rejected because Dotbot's `if:` is only supported on the `link` directive,
not on `shell`, `create`, or `clean` (confirmed in current Dotbot README).
Trying to unify would still need parallel `shell:` blocks.

### 3. Cron on VPS that auto-pulls daily

Rejected. Auto-apply on a production host without a human gate is exactly
the failure mode the design is trying to prevent.

### 4. Push-triggered GitHub Action on master

Considered and rejected (brainstorm Q: automation gate). A bad master
commit would reach the VPS instantly with no human in the loop.

### 5. Self-hosted runner on personal Mac

Rejected. Runner only works when the Mac is online; introduces a tight
dependency between personal-Mac state and VPS sync capability.

### 6. Public SSH on VPS with key auth (skip Tailscale)

Rejected. VPS is prod infra; reducing attack surface (tailnet-only) is
the whole point of routing through Tailscale.

### 7. Tailscale auth-key instead of OAuth

Rejected. Auth-keys are deprecated in the action (per action.yml
`deprecationMessage`); OAuth clients + ephemeral derived keys are the
recommended path.

## System-Wide Impact

### Interaction Graph

- **Mac invocation** (`./install` on personal/work):
  `./install` → `uname=Darwin` → `install.conf.yaml` → Dotbot → same
  helpers as today → same symlinks as today. **No behavior change.**
- **VPS invocation** (`./install` via workflow or manual):
  `./install` → `uname=Linux` → `install-linux.conf.yaml` → Dotbot → Linux
  subset of helpers → subset of symlinks (no `~/.claude/*`, no fonts).
- **Workflow invocation chain:**
  `workflow_dispatch` → Tailscale action joins tailnet → SSH snapshot step →
  SSH fetch step → SSH install step → SSH healthcheck (with retries) → on
  failure, SSH rollback → workflow fail.

### Error & Failure Propagation

- **Dotbot failure during `link`/`create`/`clean`** — Dotbot exits non-zero;
  the `ssh root@openclaw-prod './install'` step fails; healthcheck is
  skipped (its `if: !inputs.dry_run` is true but earlier step failed); the
  default step-level failure propagates; rollback step's
  `steps.healthcheck.outcome == 'failure'` is false (it's `skipped`), so
  rollback does NOT fire. **This is a gap.** Mitigation: set
  `continue-on-error: true` on the install step so healthcheck always runs,
  and let healthcheck decide — or add an explicit `outcome == 'failure' ||
  outcome == 'skipped'` guard on rollback. **Plan carries the latter.**
- **Helper script failure** under `shell:` — Dotbot reports but doesn't
  halt (`shell` defaults to `stderr: true` and continues). Our refactored
  `install_packages.sh` explicitly doesn't propagate per-package apt
  failures (by design — fail-loud-continue). Net effect: a broken helper
  results in missing tooling on VPS, not a broken install.
- **Tailscale propagation timeout** — `ping:` input waits up to 3 min;
  job timeout 15 min catches anything longer.
- **SSH hang** — per-step `timeout-minutes` catches wedged steps.

### State Lifecycle Risks

- **Rollback restores config, not system state.** `git reset --hard + ./install`
  re-applies symlinks and shell config from the prior commit. It does NOT
  uninstall apt packages added by a bad run, it does NOT revert TPM plugin
  clones, and it does NOT downgrade Oh My Zsh. For those mutations, recovery
  is forward-only: fix on master, re-sync. Document in the runbook so a
  future reader doesn't assume rollback is total.
- **Half-applied Dotbot run** — if Dotbot aborts mid-way, some symlinks are
  new, some are old. Rollback's `git reset --hard <prev> && ./install`
  re-runs Dotbot at the old SHA, which re-clean-and-relink everything
  because `link.relink: true` is set globally. Net recovery is clean.
  Edge case: if the filesystem contains a non-symlink file where Dotbot
  expects a symlink destination, it will fail with a backup path —
  documented in Dotbot.
- **Post-rollback dirty working tree** — `git reset --hard` wipes tracked
  changes. If a future VPS-side hotfix is applied in-tree and not yet
  extracted to `~/.gitconfig.local` or similar, rollback destroys it.
  Mitigation: the runbook reiterates "no in-tree edits on the VPS; all
  local divergence belongs in `~/.gitconfig.local` / `~/env.sh` /
  `~/.config/tmux/local.conf`."
- **`~/.gitconfig.local` ownership** — already exists on VPS (owned by
  root, mode 0644). Dotbot doesn't touch it. Safe.

### API Surface Parity

- `./install` — single entry point, two configs. Behavior divergence is
  documented and tested per OS.
- `./install --dry-run` — same semantics both platforms via Dotbot native
  flag + `DOTFILES_DRY_RUN` env var in helpers.

### Integration Test Scenarios

1. **Mac `./install` is unchanged** — run on personal, diff `~/.config/*`
   symlinks before/after; must be identical.
2. **Mac `./install --dry-run` touches nothing** — run on personal with a
   clean working tree; after the command, `git status` and `ls -la ~`
   unchanged.
3. **VPS `./install --dry-run` touches nothing** — first workflow run with
   `dry_run=true`; compare `readlink` output on key files before/after;
   compare `dpkg -l` before/after.
4. **Workflow dry-run round-trip completes green** — trigger via
   `gh workflow run`, verify logs show Dotbot "would link" output and no
   apt install activity.
5. **Workflow apply + healthcheck pass** — trigger with `dry_run=false`
   against a known-healthy VPS; verify all five acceptance commands pass.
6. **Simulated rollback path** — manually introduce a syntax error in
   `install-linux.conf.yaml` on a test branch; run workflow; verify
   rollback fires and restores prior HEAD.

## Acceptance Criteria

### Functional Requirements

- [ ] `./install` on personal Mac produces zero filesystem changes after
      second invocation (idempotent).
- [ ] `./install --dry-run` on personal Mac produces zero filesystem
      changes (diff `$HOME` before/after).
- [ ] `./install --dry-run` on VPS produces zero filesystem changes.
- [ ] `./install` on VPS lands all symlinks listed in `install-linux.conf.yaml`.
- [ ] Helper scripts honor `DOTFILES_DRY_RUN=1` — no `git clone`,
      `apt-get install`, or file write when set.
- [ ] `install-linux.conf.yaml` parses via Dotbot without error.
- [ ] GitHub Actions workflow runs green on `dry_run=true` against VPS.
- [ ] GitHub Actions workflow runs green on `dry_run=false` against a
      healthy VPS and passes all health checks.
- [ ] Simulated broken commit triggers rollback and restores prior HEAD.
- [ ] `tailscale ssh root@openclaw-prod echo ok` succeeds from user's Mac
      (ACL smoke test).

### Non-Functional Requirements

- [ ] Mac install behavior is byte-identical before and after this change
      (aside from the `install` wrapper diff).
- [ ] Workflow completes in < 10 min on a warm cache (Tailscale join ≤ 30s,
      SSH steps ≤ 2 min each, health check ≤ 2 min).
- [ ] No public SSH exposure introduced on VPS (all sync traffic over
      Tailscale).
- [ ] No SSH private key stored in GitHub secrets (Tailscale SSH uses
      tailnet identity).
- [ ] Rollback path is idempotent (running it twice leaves the same
      result).

### Quality Gates

- [ ] `shellcheck install helpers/install_packages.sh scripts/post-deploy-smoke.sh` passes.
- [ ] `bash -n` on all modified shell files.
- [ ] Workflow YAML passes `gh workflow view sync-vps.yml` without
      syntax errors.
- [ ] **Rollback drill completed successfully** before first real apply
      (procedure in the runbook doc).
- [ ] Plan's "Verification commands" (5 of them) all return OK after first
      live apply.
- [ ] `$GITHUB_STEP_SUMMARY` renders pre-SHA, mode, install outcome, and
      health outcome on a live run.
- [ ] PR description includes the Pre-Deploy Go/No-Go checklist + 5
      verification commands as merge gate.
- [ ] CLAUDE.md VPS row and setup section reviewed for style-match with
      work-Mac section.

## Success Metrics

- **Drift incidents:** zero post-merge weeks where VPS falls > 5 commits
  behind master without intentional delay (measured by ad-hoc
  `git log HEAD..origin/master` checks during `/pickup`).
- **Workflow MTBF:** workflow completes successfully > 95% of runs in
  first 10 invocations (inverse: rollback fires < 5% and catches real
  regressions, no false positives).
- **Regression surface:** zero issues filed against Mac install path
  after this change lands.

## Dependencies & Prerequisites

### One-time setup (preceding first workflow run)

1. **Tailscale admin:**
   - Create OAuth client with `auth_keys:write` scope and `tag:gh-actions`
     in its tags list.
   - Add to ACL:
     ```json
     "tagOwners": {
       "tag:gh-actions": ["autogroup:admin"],
       "tag:prod":       ["autogroup:admin"]
     },
     "ssh": [{
       "action": "accept",
       "src":    ["tag:gh-actions"],
       "dst":    ["tag:prod"],
       "users":  ["root"]
     }]
     ```
2. **VPS:**
   - `sudo tailscale up --advertise-tags=tag:prod`
     (or admin-console node edit — tagging only, no reauth).
   - Confirm `~/.gitconfig.local` contains the `[safe]` directory entries
     (done this session — verify in place).
3. **GitHub repo:**
   - Secrets: `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` (Settings → Secrets
     and variables → Actions).
4. **Smoke test (required before first workflow run):**
   - From user's Mac: `tailscale ssh root@openclaw-prod echo ok` must
     print `ok`. If it doesn't, diagnose ACL/tag before running workflow.

### Build-time dependencies

- Dotbot submodule at `dotbot/` bumped from `v1.19.0+17` (`ac5793c`) to
  **`v1.24.1`** (`a7fe585`) in commit `6a449ea` — required for native
  `--dry-run` support (landed upstream in v1.23.0 via `67aeaf7`).
- No new runtime dependencies introduced on Macs.
- New Ubuntu packages installed on VPS via guarded `apt-get install` — see
  package list in `install_packages.sh`.

### Runtime dependencies

- Tailscale tailnet identity (network-level).
- GitHub repo access for workflow dispatch.
- VPS Docker container `openclaw-*` running (required for health check —
  plan does not block workflow on it, but health check will rollback).

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Dotbot wrapper change breaks Mac install | Low | High | Implementation checklist step 1 verifies Mac path via diff-based tests before VPS work |
| `install-linux.conf.yaml` syntax error reaches VPS | Low | High | Workflow runs dry-run by default; YAML parsed locally before merge |
| Tailscale OAuth secret leaks | Low | High | Secret scoped to `auth_keys:write` only; ACL restricts to one host; annual rotation runbook |
| Health check false positive causes needless rollback | Medium | Low | Exponential backoff with jitter (3 attempts, ~1s/3s/7s) on the transient `openclaw status` check; permanent failures fail fast |
| Health check false negative (regression passes) | Medium | Medium | Shell smoke test catches zshrc; `/pickup` Step 2d VPS health as second line of defense |
| Rollback fails (prev SHA gone, history rewritten) | Very Low | High | Workflow explicitly checks `git rev-parse` of prev SHA; fails loudly if not resolvable |
| Concurrency queue wedges on hung run | Low | Medium | Job `timeout-minutes: 15`; step-level timeouts |
| apt drift breaks `install_packages.sh` | Medium | Low | Curated Ubuntu 24.04 package list is stable; fix the list in a PR if a package ever breaks |
| Coolify UUID rotates and breaks hardcoded container name | Medium | Low | Health check grep uses `^openclaw-` prefix, not full UUID |
| VPS-side hand-edit lost on rollback | Low | Medium | Runbook forbids in-tree edits; overrides go to `~/env.sh` / `~/.gitconfig.local` |
| Bash re-reads modified `./install` mid-run | Low | Medium | Workflow separates `git reset` and `./install` into distinct steps |

## Operational Procedures

Full procedures live in the runbook at
`docs/solutions/cross-machine/vps-dotfiles-target.md` (created as part of
this PR). The plan-level summary:

- **Pre-Deploy Go/No-Go Checklist** — must pass before the first
  `dry_run=false` run. Covers: Tailscale ACL smoke test, GitHub secrets
  present, VPS repo not shallow + clean working tree + clean submodules,
  baseline snapshot captured, rollback drill complete, monitoring panes open.
- **Rollback Drill** — push a known-bad commit to master (e.g., a
  Dotbot shell step that runs `false`), run the workflow, verify rollback
  fires and HEAD returns to the prior SHA. Must execute once before
  trusting the rollback path.
- **Roll-Forward Override** — no `force_apply` input in v1. If rollback
  fires on a false-positive health check, fix the root cause on master and
  re-run. Revisit adding an override input if this recurs.

## Resource Requirements

- **Development time:** ~4 focused hours for the single PR.
  - ~1.5h: wrapper + linux conf + helper forks + smoke script + local Mac test
  - ~1.5h: workflow YAML + Tailscale admin + secrets
  - ~0.5h: rollback drill
  - ~0.5h: runbook doc + CLAUDE.md
- **Ongoing:** ~5 min/year (OAuth secret rotation per the runbook).
- **Infrastructure:** zero new services; workflow minutes are rounding
  error at ~5 min/invocation; Tailscale user already has capacity.

## Future Considerations

- **Second Linux host** — design is already path-agnostic at repo level;
  the `concurrency.group` input and Tailscale tag let a second host join
  without workflow changes. If it has a different health shape, drop its
  assertions into `~/.dotfiles-healthcheck.sh` on that host.
- **Non-root `deploy` user on VPS** — security-review captured this as a
  posture improvement. Create `deploy` user with `NOPASSWD` sudo limited
  to `/root/.dotfiles/install`, switch ACL `users: ["root"]` to
  `["deploy"]`, and use `sudo -n ./install` inside the workflow. Deferred
  because current VPS is single-user (root) today.
- **Audit `~/.gitconfig.local` safe.directory entries** — the entries
  disable git's dubious-ownership protection for Docker volume roots.
  A compromised container could plant `.git/config` with `core.sshCommand`
  in its mounted volume; host-side `git` ops (a `/pickup` tab-completion,
  a Claude session) would then execute as root. Mitigation: narrow entries
  to specific non-writable subpaths, or stop running host-side git in
  bind-mounted paths. File as a separate ticket with elevated severity.
- **`zsh/alias.sh` Mac-only aliases** — separate ticket to guard
  `localip`, `flush`, `lscleanup`, etc., behind `$OSTYPE`. Deferral is
  safe because aliases are lazy-evaluated.

## Documentation Plan

- **New:** `docs/solutions/cross-machine/vps-dotfiles-target.md` — single
  consolidated doc (severity: high, because it covers OAuth/ACL posture
  AND deploy procedure). Sections: bootstrap, machine-local overrides,
  Tailscale OAuth + ACL setup (subsection), pre-deploy Go/No-Go,
  rollback drill, verification runbook, Tailscale-down fallback, rotation.
- **Updated:** `CLAUDE.md` — machine table (VPS row), "Setting up a
  Linux host" section, `DOTFILES_DRY_RUN` documented under Key
  Conventions, `tag:prod` guardrail note under "Things intentionally
  left as-is."
- **Updated:** HANDOFF template notes this ticket's completion + next
  steps.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-04-14-vps-dotfiles-target-brainstorm.md](../brainstorms/2026-04-14-vps-dotfiles-target-brainstorm.md) — 19 decisions carried forward including: shell+tmux parity scope (no `~/.claude/*` on VPS); OS-detecting `./install` wrapper; `--dry-run` with `DOTFILES_DRY_RUN=1` env propagation; `workflow_dispatch` manual gate; Tailscale ephemeral node transport; git-reset rollback on health failure; `concurrency: sync-vps` queue-not-cancel; per-package apt fail-loud-continue.

### Internal References

- `install:1-15` — current wrapper
- `install.conf.yaml:1-91` — directive structure to mirror
- `helpers/install_packages.sh` — apt branch that needs refactor
- `helpers/install_omz.sh` — clone-based helper needing dry-run fork
- `docs/solutions/cross-machine/corporate-mac-ssl-and-tooling-setup.md` —
  file-presence override pattern (inherited, not invented here)
- `CLAUDE.md` "Setting up the work Mac" — style template for VPS section

### External References

- Tailscale GitHub Action: https://github.com/tailscale/github-action (v4)
- Tailscale SSH + ACL: https://tailscale.com/kb/1193/tailscale-ssh
- Tailscale OAuth scopes: https://tailscale.com/kb/1623/trust-credentials#scopes
- Tailscale OAuth lifecycle: https://tailscale.com/kb/1215/oauth-clients
- Tailscale Configuration Audit Logs: https://tailscale.com/docs/features/logging/audit-logging
- Tailscale security hardening: https://tailscale.com/kb/1196/security-hardening
- GitHub Actions deployments/environments: https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- GitHub Actions deployment protection rules: https://docs.github.com/actions/deployment/protecting-deployments/configuring-custom-deployment-protection-rules
- GitHub Actions `$GITHUB_STEP_SUMMARY`: https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#adding-a-job-summary
- GitHub Actions workflow_dispatch: https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#onworkflow_dispatch
- GitHub Actions concurrency: https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#concurrency
- GitHub Actions step outputs: https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#setting-an-output-parameter
- GitHub Actions status check funcs: https://docs.github.com/en/actions/learn-github-actions/expressions#status-check-functions
- Dotbot README: https://github.com/anishathalye/dotbot
- apt-get(8) Ubuntu 24.04: https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html
- Retry pattern with exponential backoff: https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/retry-backoff.html

### Related Work

- Prior cross-platform work in this repo: `67aa164` (cross-platform
  package installer), `72b1a9a` (Homebrew guards for Linux portability)
- Recent VPS-touching work: `74f035a` (Forge bridge registration),
  `5327c1e` (tmux continuum fix — illustrates cost of drift since VPS
  didn't have this fix until it was pulled this session)
