---
date: 2026-04-14
topic: VPS as a first-class dotfiles sync target
status: brainstorm
---

# VPS Dotfiles Target — Brainstorm

## What We're Building

Promote the OpenClaw VPS (`root@openclaw-prod`, Ubuntu 24.04, Hetzner,
Coolify-managed Docker host) from an ad-hoc clone of this repo into a
**first-class dotfiles sync target** alongside `personal` and `work` Macs.

Goals:

- Safe, repeatable install path on Linux that skips Mac-only ceremony
  (Homebrew, fonts, iTerm plist, osx defaults, chsh).
- Honor the existing per-machine override contract (`~/env.sh`,
  `~/.gitconfig.local`, `~/.config/tmux/local.conf`) — no hostname sniffing.
- Zero risk to the current Mac install pipeline — Macs must behave identically
  before and after.
- Zero risk to running production services on the VPS — Docker volumes,
  Coolify-managed services, Forge agents, OpenClaw gateway all untouched.
- Keep the VPS from silently drifting 50+ commits behind master again.

Non-goals:

- Running Claude Code interactively on the VPS (no `~/.claude/*` parity).
- iTerm2, macOS defaults, fonts, or any GUI concern.
- Generalizing to non-Debian distros — VPS is pinned to Ubuntu 24.04.

## Why This Approach

Research shows the repo is already ~80% Linux-ready thanks to commits
`67aa164` (cross-platform package installer) and `72b1a9a` (Homebrew guards).
The remaining drag points are narrow: `zsh/alias.sh` has unguarded macOS
commands, `claude/settings.json` hardcodes `/Users/dvillavicencio`, and
CLAUDE.md's machine table has no Linux row.

Rather than retrofit one universal install path, we add a **parallel Linux
profile** that reuses cross-platform pieces and explicitly skips Mac-only
pieces. This keeps the Mac install path unchanged (no regression risk for the
two most-used targets) while giving the VPS a clear, auditable entry point.

The install mechanism is an OS-detecting `./install` wrapper that picks
between `install.conf.yaml` (Mac) and `install-linux.conf.yaml` (VPS) based on
`uname`. Same command on every host; different config under the hood. One
fewer thing to remember than a separate `./install-linux` script.

## Key Decisions

### Scope: shell + tmux parity only

Symlinked on VPS: `zshenv`, `zshrc`, `gitconfig`, `gitignore`, `gitattributes`,
`tmux.conf`, `btop.conf`, `lazygit/config.yml`, `topgrade.toml`,
`nvim/lua/custom`, `starship.toml` (if created).

**Not** symlinked on VPS: `~/.claude/*` (no Claude Code interactive use),
iTerm plist, macOS defaults, any `~/Library/*` destination.

Rationale: smallest blast radius that still delivers the actual need — a
familiar shell and mosh-friendly tmux on the VPS. Adding Claude parity later
is a separate decision with its own scope.

### Install shape: OS-detecting `./install` entry

```bash
#!/usr/bin/env bash
case "$(uname)" in
  Darwin) CONFIG=install.conf.yaml ;;
  Linux)  CONFIG=install-linux.conf.yaml ;;
  *)      echo "Unsupported OS: $(uname)"; exit 1 ;;
esac
exec bin/dotbot -d . -c "$CONFIG" "$@"
```

Two config files, one entry point. Users never pick a profile — `uname` does.

### Safety net: `--dry-run` flag

First VPS run goes through `./install --dry-run`, which surfaces every
Dotbot action (link created, link skipped, existing file preserved) without
touching the filesystem. Manual diff review before the real run. No snapshot
file, no canary mode — keeping the surface minimal.

### Sync cadence: GitHub Actions, manual trigger

A new workflow (`.github/workflows/sync-vps.yml`) with `workflow_dispatch`
trigger. Input `dry_run: boolean` defaults to `true`. You invoke via
`gh workflow run sync-vps.yml` or the GitHub UI when you're ready for the
VPS to catch up.

No `on: push` trigger — a bad commit on master should not instantly break
production. The human-in-the-loop gate is the point.

### Transport: Tailscale GitHub Action

The cloud runner joins the tailnet ephemerally via `tailscale/github-action@v2`
with an OAuth client scoped to `tag:gh-actions`. Tailscale ACL restricts that
tag to `ssh root@openclaw-prod` only. No public SSH on the VPS, no self-hosted
runner to babysit, audit log in Tailscale admin.

### CLAUDE.md updates

Add a third row to the machine table: `vps` / `Ubuntu 24.04` / `Hetzner
shared` / `OpenClaw + Forge host`. Add a "Setting up the VPS" section
mirroring "Setting up the work Mac" — with the Ubuntu-specific setup notes
(safe.directory entries in `~/.gitconfig.local`, `./install` on Ubuntu).

## Resolved Questions

- **Scope** — shell + tmux parity only; no Claude/* on VPS.
- **Install shape** — OS-detecting `./install` wrapper.
- **Safety net** — `--dry-run` flag (no snapshot, no canary).
- **Sync cadence** — GitHub Actions.
- **Automation gate** — `workflow_dispatch` manual, dry-run default.
- **Transport** — Tailscale GitHub Action (ephemeral tailnet node,
  `tag:gh-actions` ACL scoped to `ssh root@openclaw-prod`).
- **Distro** — Ubuntu 24.04 confirmed on VPS; apt branch of
  `install_packages.sh` is the right path.
- **Q1: apt idempotency** — Audit `install_packages.sh`'s apt branch before
  first live run; add `command -v X || apt-get install X` guards where missing.
  Don't trust apt's implicit no-op behavior.
- **Q2: NVM/Node on VPS** — **Skip.** OpenClaw runs Node inside Docker;
  user-level Node on the host is unused weight. Linux profile omits
  `install_nvm.sh` and `install_node.sh`.
- **Q3: chsh** — **Already zsh on VPS** (`/usr/bin/zsh` is root's default
  shell). Verified live. Install-linux profile can skip the chsh directive
  entirely; no risk.
- **Q4: env.sh** — Document `~/env.sh` as **optional** in the CLAUDE.md VPS
  setup section with an empty template + placeholder comments. No required
  exports today; contract stays consistent across machines.
- **Q5: Health check** — **Bake into the GH Action workflow** as a post-sync
  step. Verify `openclaw-d95veq7chb3d8gllyj6vhpqy` container is still running
  and `openclaw status --deep` reports zero `CRITICAL`/`ERROR` lines. Fail
  the workflow loudly on regression.
- **Q6: Ownership** — **Stay root-owned.** Single operational user on the
  VPS; no non-root user on the roadmap. Install target remains `/root/.dotfiles`.
- **Rollback mechanics** — **Git-based reset.** Workflow records
  `git rev-parse HEAD` before install. On health-check failure, auto-runs
  `git reset --hard <prev-sha> && ./install-linux` and fails the workflow
  loudly. Relies on prior HEAD being healthy — safe assumption since health
  checks gate every successful sync.
- **Dry-run fidelity** — **Native Dotbot `--dry-run` (v1.24.1) + `DOTFILES_DRY_RUN`
  as defense-in-depth.** The wrapper passes `--dry-run` through to Dotbot; all
  built-in plugins (link/create/clean/shell) preview without mutating the
  filesystem. A `DOTFILES_DRY_RUN=1` env var is also exported for helpers
  invoked directly outside Dotbot (e.g., `bash helpers/install_omz.sh`).
  *Note: the original plan had the wrapper STRIP `--dry-run` and rely on
  idempotent no-op for link/create/clean. A reviewer reproduced that this
  mutated a fresh `HOME`, so Dotbot was bumped from v1.19.0+17 → v1.24.1
  to gain native dry-run support (see PR `6a449ea`).*
- **Tailscale OAuth hygiene** — **Documented rotation runbook** at
  `docs/solutions/cross-machine/tailscale-gh-actions-oauth-setup.md` covering
  creation, ACL setup, GH secrets config, and rotation procedure. Annual
  rotation reminder via Forge ticket.
- **apt upstream drift** — **Fail-loud per-package, continue install.**
  Package install failures print `::warning::` to the workflow log but don't
  halt Dotbot. A drifted package shouldn't block symlinks from landing.
- **Fresh Linux bootstrap** — **Documented one-liner in CLAUDE.md** under a
  new "Setting up a Linux host" section:
  `apt install git zsh && git clone ... ~/.dotfiles && cd ~/.dotfiles && ./install`.
  No bootstrap script; no curl-pipe-bash anti-pattern.
- **Concurrency** — **GitHub Actions `concurrency` group.** Workflow gets
  `concurrency: { group: sync-vps, cancel-in-progress: false }`. Second run
  queues behind the first. One line, zero code, prevents Dotbot reentrancy
  races.

## Next Steps

- Resolve Open Questions with the user.
- Then: `/ce:plan` to turn this into an implementation plan covering:
  - New files: `install-linux.conf.yaml`, `.github/workflows/sync-vps.yml`
  - Modified files: `install` (OS-detect wrapper), `CLAUDE.md` (machine
    table + VPS setup section), possibly `install_packages.sh` (idempotency
    audit)
  - Tailscale admin: OAuth client + `tag:gh-actions` ACL
  - GitHub: `TS_OAUTH_CLIENT_ID` + `TS_OAUTH_SECRET` secrets
  - VPS one-time prep: move `safe.directory` to `~/.gitconfig.local` (done
    in this session)
