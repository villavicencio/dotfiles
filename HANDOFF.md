# HANDOFF — 2026-04-15, afternoon

## What We Built

### Shipped to master (13 commits this session)

- **`67e6a41` — OSC 52 clipboard + Brewfile docker-desktop.** Added `set -g set-clipboard on` to `tmux/tmux.general.conf` so mosh→VPS-tmux yanks land on local Mac clipboard. Renamed `brew/Brewfile` cask `docker` → `docker-desktop` per Homebrew's 2026 rename.
- **`33bdb8c → 9538bdc` (PR #22 merged) — VPS as a first-class dotfiles sync target.**
  - `install` wrapper now OS-detects and routes to `install-linux.conf.yaml` on Linux.
  - New `install-linux.conf.yaml` — trimmed Linux profile (no Claude/*, no fonts, no NVM/Node, no chsh).
  - Forked helper DRY_RUN guards on `install_omz.sh`, `install_tmux.sh`, `install_nvim.sh`, `install_packages.sh` (apt branch).
  - New `scripts/post-deploy-smoke.sh` with pluggable `~/.dotfiles-healthcheck.sh` hook.
  - New `.github/workflows/sync-vps.yml` — `workflow_dispatch` manual trigger, Tailscale `@v4` ephemeral runner, SHA-snapshot + install + health-check + git-reset rollback on failure, `$GITHUB_STEP_SUMMARY` table.
  - Consolidated runbook at `docs/solutions/cross-machine/vps-dotfiles-target.md` (bootstrap, OAuth setup, Go/No-Go, rollback drill, 5 verification commands, mosh fallback, annual rotation).
  - CLAUDE.md gets a VPS row, `DOTFILES_DRY_RUN` convention, "Setting up a Linux host" section, and a `tag:prod` SSH-root guardrail.
  - Dotbot submodule bumped from **v1.19.0+17 → v1.24.1** for native `--dry-run` support (required mid-review after a reviewer reproduced fresh-host mutations).
- **`2ae5f36 → bd22ada` (PR #24 merged + reverted) — Rollback drill.** Pushed an intentional `[false, "DRILL..."]` shell step, triggered `dry_run=false`, confirmed rollback fired and reset VPS to baseline. Reverted immediately after.
- **`305f478` — Smoke script fix.** Replaced `zsh -i -c exit` with `zsh -i -c true` after the drill surfaced a false-positive in the health check. Full rationale in the code comment so future edits don't regress it.
- **`75e89b8`, `fbbd0c1` — Three compound docs.** Every non-trivial gotcha from today is now searchable in `docs/solutions/`:
  - `code-quality/zsh-dash-i-c-exit-false-positive-health-check.md` (High, 195 lines)
  - `cross-machine/tailscale-tag-acl-ssh-failure-modes.md` (High, 281 lines)
  - `code-quality/dotbot-dry-run-requires-v1-23-or-later.md` (Medium, 210 lines)

### Ticket filed

- **villavicencio/dotfiles#23** — Fix SC2218 in `helpers/install_tmux.sh` (`handle_error` called on line 17 before definition on line 22). Latent bug; caught during PR #22 review. On the Dotfiles kanban board.

### VPS operational state

`root@openclaw-prod` is now **at master HEAD** (`fbbd0c1`) and running the full new sync infrastructure. First real apply completed green with all 5 acceptance commands passing. Tailscale `tag:prod` is authoritative, OAuth client live (`TS_OAUTH_CLIENT_ID` + `TS_OAUTH_SECRET` in GH secrets), key expiry disabled, and the workflow + rollback path have been validated against real infrastructure.

## Decisions Made

- **Submodule bumps are commits worth doing immediately, not deferring.** Discovering mid-review that our vendored Dotbot predated native `--dry-run` was load-bearing for the "safe preview" contract we'd documented. Bumped to v1.24.1 in one focused commit (`6a449ea`) rather than hacking around it.
- **Plan + brainstorm reconciliation preserves the learning arc.** After upgrading Dotbot I rewrote the plan's wrapper code block and directive table to reflect the new reality — but kept explicit historical notes saying "the original design was X; reviewer proved it unsafe; corrected by bumping." Git history alone can tell the story, but the inline notes mean someone re-reading the plan sees the *reasoning* evolve, not just polished outcomes.
- **`autogroup:admin` in ACL `ssh` rules must come BEFORE any pre-existing `check`-mode rule** — Tailscale SSH rules are first-match-wins; a `check` rule that matches first demands interactive re-auth that scripted SSH can't satisfy.
- **Admin-assign tags via the UI; never rely on `tailscale up --advertise-tags=`** for initial tag bring-up — self-advertisement goes through a pending-approval dance that leaves ACL rules failing to match.
- **Disable key expiry on every provisioned VPS as step one.** Default 90-day expiry is a foot-gun for headless infra. Captured in `tailscale-tag-acl-ssh-failure-modes.md`.
- **On the transition from old-Dotbot-on-VPS to new-Dotbot-on-VPS, a one-time manual `git reset --hard origin/master` without running `./install` is the cleanest bootstrap.** The workflow's dry-run can't preview against the new wrapper until the new wrapper exists on disk. After the one-time manual sync, every future workflow run works as designed.
- **`zsh -i -c true` — NOT `-c exit`.** `exit` inherits last command's status; zshrcs commonly end with `[[ -f ... ]]` guards that return non-zero. Same applies to bash. Any health check probing shell init must use `true` or `exit 0` or `:`.

## What Didn't Work

- **First live `dry_run=true` workflow run — failed** with `dotbot: error: unrecognized arguments: --dry-run`. Root cause: VPS was still on pre-PR master where the wrapper stripped the flag and the old Dotbot didn't understand it. The workflow's dry-run path invokes `./install --dry-run` against the **current** VPS HEAD (my P1 #1 fix), so the one-time bootstrap had to happen before the workflow could work. Recovery: manual `git reset --hard origin/master` on the VPS, then retried the workflow. Works every time post-bootstrap.
- **First `dry_run=false` (real apply) — rolled back due to smoke-check false positive.** Install succeeded, health check ran `zsh -i -c exit` → returned 1 → rollback fired. Root cause in the `-c exit` anti-pattern. Fix in `305f478`, second apply green.
- **Naive `tailscale up --advertise-tags=tag:prod` on an expired node.** Three cascading failures: key expiry blocks operation → ACL edits reveal `autogroup:self` no longer matches a tagged node → even after adding `autogroup:admin → tag:prod` SSH rule, the self-advertised tag stays in pending-approval limbo. Solved only by admin-assigning from the UI. All three documented in `tailscale-tag-acl-ssh-failure-modes.md`.
- **Plan's "link/create/clean are idempotent no-ops, so dry-run is safe" reasoning.** True on already-bootstrapped hosts; false on fresh `HOME`. Reviewer reproduced real filesystem mutations during "dry-run." Required the Dotbot submodule bump to fix cleanly.

## What's Next

Priority-ordered:

1. **Issue #23 — Fix SC2218 in `helpers/install_tmux.sh`.** Three-line hoist (move `handle_error()` + `log_message()` definitions above their first use at line 17). Latent bug; triggers only on failed `touch ~/.config/tmux/plugins/tpm/install_tmux.log`. Tiny PR, quick win.
2. **Cross-machine sync test on the work Mac.** Run `./install` on the FedEx Mac to verify Dotbot v1.24.1 bump, the new OS-detect wrapper, `install-linux.conf.yaml` (untouched on Mac path), and all helper DRY_RUN guards behave identically to personal. Acceptance: no symlink changes, idempotent second run.
3. **Regular VPS sync cadence.** When master has meaningful dotfile changes: `gh workflow run sync-vps.yml --repo villavicencio/dotfiles -f host=openclaw-prod -f dry_run=true` → review step summary → `-f dry_run=false`. The pipeline is now trusted.
4. **OAuth secret rotation reminder — 2027-04-14.** Runbook documents the procedure (delete old client first, then create new). File a Forge ticket when due.
5. **Optional follow-up tickets** (nothing blocking):
   - Fix `claude/commands/ticket.md` in this repo — still copy-pasted from the dataworks-website config (wrong repo target + project ID). That's why `/ticket` fired against the wrong board today.
   - Sidecar rename cleanup for orphaned entries in `~/.config/tmux/window-meta.json` (brainstorm Q2 deferral from earlier — no ticket yet; file if/when it bites).

## Gotchas & Watch-outs

- **Don't use `tailscale up --advertise-tags=` for initial tag assignment.** Use admin UI "Edit ACL tags" instead. Self-advertisement is for scripted auth-key workflows (GH Actions ephemeral runners) — there it's correct. For a headless server, prefer admin-assign.
- **Disable key expiry on any new tailnet-member server the moment you add it.** Default expiry will bite exactly when you least want it to.
- **ACL `ssh` rule order matters** — first-match-wins. Put `accept` rules above `check` rules if the same source+dst could match both.
- **`tailscale status --json | jq '.Peer | to_entries[] | select(.value.HostName == "X") | .value.Tags'`** is the ground-truth check for tag authoritativeness. Admin UI badges can lie (show the tag as applied even when coordinator state is still pending).
- **Dotbot v1.24.1 is quieter by default** — `./install` no longer prints "Link exists" for every no-op. Verify idempotency by diffing `find ~/.config ~/.claude -type l`, not by log-line counting.
- **`~/.gitconfig.local` on the VPS has `[safe] directory` entries for Docker volumes.** Security-review finding #8 flagged this as an elevated-risk area (a compromised container could plant `.git/config` with `core.sshCommand` in a mounted volume and escalate to root). Not blocking but worth a narrower-subpath audit in a future session.
- **Dry-run truly does nothing on VPS now** (Dotbot v1.24.1 + pass-through wrapper). If you want to test what `./install` would do, use the workflow with `dry_run=true`. If you want to apply, use `dry_run=false`. No third mode.
- **The tmux OSC 52 e2e test through mosh** was not re-verified after the final VPS sync landed. VPS tmux should have `set-clipboard on` now (it's in the committed `tmux.general.conf`). Worth a 30-second check next time you're in a mosh session: enter tmux copy mode, yank something, `pbpaste` locally. Low priority — we confirmed it works live; just haven't confirmed it survives a fresh VPS reconnect.
- **AGENTS.md auto-generation.** Something on the system (possibly a non-Claude agent tool) generated `AGENTS.md` at 9:55 AM today — a mechanically-substituted "Codex" version of CLAUDE.md with multiple factual errors. Deleted. If it regenerates, consider `.gitignore`-ing it.
