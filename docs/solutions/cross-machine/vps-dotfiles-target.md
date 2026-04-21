---
title: "Sync dotfiles to a Linux VPS via GitHub Actions over Tailscale"
date: 2026-04-14
last_updated: 2026-04-20
category: cross-machine
tags:
  - vps
  - linux
  - ubuntu
  - tailscale
  - github-actions
  - dotbot
  - deploy
  - rollback
  - oauth
severity: High
component:
  - install
  - install-linux.conf.yaml
  - .github/workflows/sync-vps.yml
  - scripts/post-deploy-smoke.sh
  - helpers/install_packages.sh
status: Resolved
scope:
  - openclaw-prod (Ubuntu 24.04)
  - any future Linux host with root access and tailnet connectivity
---

# Sync dotfiles to a Linux VPS via GitHub Actions over Tailscale

## Overview

This runbook covers the end-to-end setup for syncing this dotfiles repo to
a Linux host (currently `openclaw-prod`, an Ubuntu 24.04 Hetzner VPS on
the tailnet as `tag:prod`). The sync is driven by a manually-triggered
GitHub Actions workflow that joins the tailnet as an ephemeral node, runs
`./install` over SSH, health-checks the result, and auto-rolls-back on
failure.

Two audiences:

- **First-time VPS bootstrap** — you're setting up a fresh Linux host.
  Start at [Bootstrap](#bootstrap-fresh-linux-host).
- **First-time workflow setup** — you have a working VPS and want to
  enable the GitHub Actions sync path. Start at
  [Tailscale OAuth + ACL setup](#tailscale-oauth--acl-setup).

## Bootstrap (fresh Linux host)

Ubuntu 24.04 assumed. Adapt package manager for other distros (not tested).

```bash
# 1. Install the minimum needed to clone + run the installer.
apt-get update && apt-get install -y git zsh

# 2. Clone the repo.
git clone https://github.com/villavicencio/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 3. Preview what will change.
./install --dry-run

# 4. Apply.
./install
```

The `./install` wrapper picks `install-linux.conf.yaml` automatically based
on `uname`. No flags or configuration needed.

### Machine-local overrides

Three files are NOT checked in and are machine-specific. Create whichever
apply:

- `~/.gitconfig.local` — git identity + `safe.directory` entries for any
  Docker volumes you run git commands against from the host:
  ```ini
  [user]
      email = villavicencio.david@gmail.com
  [safe]
      directory = /var/lib/docker/volumes/<project-uuid>_<volume>/_data
      directory = /var/lib/docker/volumes/<project-uuid>_<volume>/_data/<subpath>
  ```
  Note: `safe.directory` disables git's dubious-ownership protection for
  listed paths. A compromised container with a bind-mount on that path
  could plant a `.git/config` with `core.sshCommand` and execute code as
  root when you next `git -C` into the path. Narrow entries to specific
  non-writable subpaths where possible.

- `~/env.sh` — optional. Sourced silently at end of `zshrc`. Use for any
  host-specific exports (e.g., a Docker volume path a shell helper needs).

- `~/.config/tmux/local.conf` — optional. Sourced by `tmux.conf` if
  present. Use for host-specific tmux tweaks (e.g., different
  continuum save interval).

## Tailscale OAuth + ACL setup

One-time setup. Required before any workflow run can reach the VPS.

### 1. Tag the VPS

```bash
# On the VPS (or via Tailscale admin console → Machines → openclaw-prod → Edit tags):
sudo tailscale up --advertise-tags=tag:prod
```

### 2. ACL edits

In https://login.tailscale.com/admin/acls/file, add or merge:

```json
{
  "tagOwners": {
    "tag:gh-actions": ["autogroup:admin"],
    "tag:prod":       ["autogroup:admin"]
  },
  "grants": [
    // GH Actions runner needs raw OpenSSH (tcp:22) to the VPS. The ssh{}
    // block below only governs Tailscale SSH (separate auth path); this
    // grant is what gives tag:gh-actions peer-list visibility AND tcp:22
    // connectivity to tag:prod. Omitting it makes the runner unable to
    // see openclaw-prod in its tailnet peer list, which surfaces as DNS
    // lookup failures — see
    // tailscale-grants-vs-ssh-block-raw-ssh-2026-04-20.md.
    {"src": ["tag:gh-actions"], "dst": ["tag:prod"], "ip": ["tcp:22"]}
  ],
  "ssh": [
    {
      "action": "accept",
      "src":    ["tag:gh-actions"],
      "dst":    ["tag:prod"],
      "users":  ["root"]
    }
  ],
  "tests": [
    // Save-time regression guard. Tailscale refuses to save an ACL where
    // a test fails, so if a future edit drops the grant above, the save
    // will surface the regression instead of silently shipping it.
    {"src": "tag:gh-actions", "accept": ["tag:prod:22"]}
  ]
}
```

Any node tagged `tag:prod` from now on will be SSH-root-accessible from
the GitHub Actions runner. **Do not apply `tag:prod` to a new node without
reviewing this ACL first.**

**Why both `grants` and `ssh`?** They govern two different auth paths.
`grants` controls raw IP connectivity (OpenSSH on port 22, which the
workflow uses via `ssh root@openclaw-prod`). `ssh` controls Tailscale
SSH (invoked via `tailscale ssh <host>`, a separate auth layer). The
runbook keeps the `ssh` block for operator convenience (`tailscale ssh`
from your laptop), but the workflow-critical path is the `grants`
entry.

### 3. Create the OAuth client

Tailscale admin → Settings → OAuth clients → **Generate OAuth client…**:

- Description: `github-actions dotfiles sync`
- Scopes: `auth_keys` (write)
- Tags: `tag:gh-actions`

Copy the client ID and secret. You will not see the secret again.

### 4. Upload GitHub secrets

Repo → Settings → Secrets and variables → Actions → **New repository secret**:

- `TS_OAUTH_CLIENT_ID` — the client ID from step 3
- `TS_OAUTH_SECRET` — the secret from step 3

### 5. Smoke test before any workflow run

From a tailnet-connected client (personal Mac), test the **exact path
the workflow uses** — raw OpenSSH over tailnet, not Tailscale SSH:

```bash
ssh root@openclaw-prod 'echo ok'
```

Should print `ok`. If it fails, diagnose the ACL grant (not the `ssh`
block) or tag before running the workflow.

**Important:** deliberately use plain `ssh`, not `tailscale ssh`. The
workflow invokes `ssh root@openclaw-prod` against sshd on port 22 —
that's raw OpenSSH-over-tailnet, which needs the `grants` entry above.
`tailscale ssh` takes a different auth path (the `ssh` block), so a
passing `tailscale ssh` smoke test can mask a missing `grants` entry —
exactly the failure mode that caused issue #42 (2026-04-20).
`StrictHostKeyChecking=accept-new` in the workflow IS functional for
raw OpenSSH — the runner caches the VPS host key on first contact.

### 6. What `dry_run=true` actually does

The workflow's `dry_run=true` toggle surfaces two independent signals, and
knowing which is which prevents a surprise on apply:

- **"Pending commits"** in the run's step summary — authoritative list of
  what would land on a real apply. Produced from `git log HEAD..origin/master`
  after a metadata-only `git fetch` (the working tree is intentionally not
  reset, because `/root/.dotfiles/*` is the backing store for live symlinks).
- **`./install --dry-run`** output in the Install step log — runs against
  the VPS's **current** HEAD, not `origin/master`. So a new `- link:` entry
  in a pending commit will NOT appear as `Would create symlink ...` in the
  dry-run; it only shows up on apply. Dotbot v1.24.1 handles the flag
  natively across `link` / `create` / `clean` / `shell` — mutation-free.

Treat dry-run as a connectivity + installer-sanity probe. For a per-symlink
preview of a specific commit, run the local fresh-`$HOME` recipe
(see [`CLAUDE.md`](../../../CLAUDE.md)). Full analysis:
[sync-vps-dry-run-previews-current-head.md](sync-vps-dry-run-previews-current-head.md).

## Pre-Deploy Go/No-Go Checklist

Run top-to-bottom before every `dry_run=false` workflow invocation,
especially the first. Any FAIL = STOP.

1. **ACL still works** for the workflow path (raw OpenSSH, not Tailscale SSH):
   ```bash
   ssh root@openclaw-prod 'echo ok'
   ```
   Use plain `ssh` here to match what the workflow does. `tailscale ssh`
   exercises a different ACL path (`ssh` block) and can pass while the
   workflow-critical `grants` entry is missing — see the note in the
   [smoke test section](#5-smoke-test-before-any-workflow-run).

2. **GitHub secrets still present**:
   ```bash
   gh secret list --repo villavicencio/dotfiles | grep -E 'TS_OAUTH_CLIENT_ID|TS_OAUTH_SECRET'
   ```

3. **VPS repo is non-shallow, clean, and submodules clean**:
   ```bash
   tailscale ssh root@openclaw-prod '
     cd /root/.dotfiles
     [ "$(git rev-parse --is-shallow-repository)" = "false" ] || { echo FAIL shallow; exit 1; }
     [ -z "$(git status --porcelain)" ] || { echo FAIL dirty; exit 1; }
     git submodule status | grep -vE "^ " && { echo FAIL submodule; exit 1; } || true
     echo OK
   '
   ```

4. **Baseline snapshot saved locally**:
   ```bash
   tailscale ssh root@openclaw-prod '
     cd /root/.dotfiles && git rev-parse HEAD
     ls -la ~/.config/zsh ~/.config/tmux ~/.config/git
     docker ps --format "{{.Names}} {{.Status}}"
   ' | tee ~/vps-baseline-$(date +%F).txt
   ```

5. **Rollback drill has been run at least once** on this workflow. See
   [Rollback Drill](#rollback-drill).

6. **Three monitoring panes open before flipping to apply**:
   - Pane A: `gh run watch` (or the Actions tab).
   - Pane B: `tailscale ssh root@openclaw-prod 'journalctl -fu docker'`.
   - Pane C: `tailscale ssh root@openclaw-prod 'docker logs -f $(docker ps --filter name=openclaw- -q | head -1)'`.

## Rollback Drill

Execute **before** relying on the rollback path for the first time.

1. On master, confirm current `./install` runs green. Note the SHA — call
   it `A`.
2. Push a known-bad commit: append an intentionally failing shell step to
   `install-linux.conf.yaml`, e.g.:
   ```yaml
   - shell:
       - [false, "drill-intentional-fail"]
   ```
   Note the new SHA — call it `B`.
3. Dispatch the workflow with `dry_run=false`:
   ```bash
   gh workflow run sync-vps.yml -f dry_run=false && gh run watch
   ```
4. Expected:
   - Install step fails (`false` returns exit 1).
   - Rollback step fires (condition: `failure() && !dry_run && install.outcome == 'failure'`).
   - Workflow marked red.
5. Verify on VPS: `cd /root/.dotfiles && git rev-parse HEAD` equals SHA
   `A`. Run the [verification commands](#verification) — all must pass.
6. Revert commit `B` on master.

If step 5 fails (HEAD is not `A`), **rollback is broken** — do not rely
on the workflow for live work until you've diagnosed and fixed it.

## Verification

Run after every live apply. All five should print OK.

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

**Known gap**: command 2 catches zshrc-init regressions on new sessions
but does NOT detect a broken `tmux.conf` affecting already-attached tmux
sessions. After a deploy that touched `tmux/tmux.conf`, re-source in an
attached session: `tmux source-file ~/.config/tmux/tmux.conf`.

## Tailscale-down fallback (mosh)

If Tailscale itself is degraded (MagicDNS fails, coordinator unreachable,
GH runner can't join the tailnet), the workflow is unavailable. Manual
recovery path:

```bash
# Get the VPS's tailnet IP (if MagicDNS is down but tailscaled is up):
TS_IP=$(tailscale ip -4 openclaw-prod)

# Connect via mosh (survives NAT changes, roams better than SSH):
mosh "root@$TS_IP"
# Then: cd /root/.dotfiles && git pull && ./install
```

If the Mac's own `tailscaled` is down, restart it:
`sudo launchctl kickstart -k system/com.tailscale.ipnextension`.

## Annual OAuth rotation

OAuth client secrets do not expire by default. Rotate annually — reduces
the window if the secret ever leaks via shell history, backup, etc.

**Procedure** (do NOT create new before deleting old — you want overlap
minimized):

1. Create a new OAuth client in Tailscale admin (same scopes + tags).
2. Update `TS_OAUTH_CLIENT_ID` and `TS_OAUTH_SECRET` in GitHub repo secrets.
3. Trigger a `dry_run=true` workflow run to confirm new creds work.
4. Delete the old OAuth client in Tailscale admin.
5. Review https://login.tailscale.com/admin/logs for any unexpected
   `tag:gh-actions` node activity in the prior window.

**Calendar reminder**: 2027-04-14. File as Forge ticket when due.

## Related

- Plan: [docs/plans/2026-04-14-feat-vps-dotfiles-sync-target-plan.md](../../plans/2026-04-14-feat-vps-dotfiles-sync-target-plan.md)
- Brainstorm: [docs/brainstorms/2026-04-14-vps-dotfiles-target-brainstorm.md](../../brainstorms/2026-04-14-vps-dotfiles-target-brainstorm.md)
- [tailscale-grants-vs-ssh-block-raw-ssh-2026-04-20.md](tailscale-grants-vs-ssh-block-raw-ssh-2026-04-20.md)
  — why the ACL needs both a `grants` entry and an `ssh` block, and why
  a missing grant looks like a DNS failure.
- [tailscale-tag-acl-ssh-failure-modes.md](tailscale-tag-acl-ssh-failure-modes.md)
  — other Tailscale ACL failure modes encountered during VPS bring-up
  (key expiry, `autogroup:self` on tagged nodes, self-advertised-tag
  approval limbo).
- Dotbot `--dry-run` support: https://github.com/anishathalye/dotbot
  (vendored at v1.24.1 — native `--dry-run` covers `link`/`create`/`clean`/`shell`.
  The wrapper also exports `DOTFILES_DRY_RUN=1` as defense-in-depth for helpers
  invoked directly outside Dotbot.)
- Tailscale GitHub Action v4: https://github.com/tailscale/github-action
- Tailscale SSH: https://tailscale.com/kb/1193/tailscale-ssh
- Tailscale Grants: https://tailscale.com/kb/1324/acl-grants
- Configuration Audit Logs: https://login.tailscale.com/admin/logs
