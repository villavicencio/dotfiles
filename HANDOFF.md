# HANDOFF — 2026-05-21 (PDT, evening)

#79 closed via PR #80 — sync-vps decommissioned after a premise-shift investigation. **Issue board is now empty, no open PRs, working tree clean.** First clean-slate handoff since the Node-24 sweep started 2026-05-11.

## What We Built

- **PR #80 — `ci: decommission sync-vps.yml (closes #79)`** (squash-merged into `01890bc`, branch deleted). 5 files, 24 insertions / 275 deletions.
  - **Deleted:** `.github/workflows/sync-vps.yml`, `scripts/post-deploy-smoke.sh` (only invoked by sync-vps).
  - **Edited:**
    - `CLAUDE.md` — dropped "one VPS" framing in the opening sentence, removed the VPS row from the machines table, removed the `## Setting up a Linux host (VPS)` section, removed the Tailscale `tag:prod` / `tag:gh-actions` ACL paragraph. Added replacement note about preserving generic Linux Dotbot infra under "Things intentionally left as-is."
    - `.github/workflows/install-matrix.yml` — rewrote comment #2 in the "what this matrix does NOT validate" block (sync-vps was cited there as the workflow that covered the tailnet path).
    - `docs/solutions/cross-machine/vps-dotfiles-target.md` — retire-noted (NOT deleted). `status: Resolved → Retired`, prominent banner at top with date stamp, knowledge preserved for any future Linux target.
  - **Preserved as revival infrastructure:** `install-linux.conf.yaml`, `case Linux)` branch in `./install`, `helpers/*.sh` `uname` guards. `claude/commands/pickup.md` Step 2c left intact (already updated 2026-05-20 to snapshot Hermes/Axiom/host health, gates on `git remote contains "openclaw"` so dotfiles `/pickup` skips it).

## Decisions Made

- **Re-clone (option 1 in #79) was rejected** after VPS inspection revealed the dotfiles tree was deliberately removed during the 2026-05-20 OpenClaw destroy, not silently lost. The box is now `openclaw-prod-hil` hosting Hermes-Atlas (deployed 2026-05-17) + Claude Code (deployed 2026-05-19). Re-cloning would have overlaid Dotbot symlinks onto the freshly-shaped Hermes/Claude environment. **Decommission (option 2) was the correct call.**
- **Generic Linux Dotbot support preserved.** Even though my AskUserQuestion option text listed `install-linux.conf.yaml` and helpers' Linux branches as deletion targets, on closer inspection they have no `openclaw-prod` coupling and serve as a revival path for any future Linux host. The retire-noted runbook is the canonical revival reference.
- **Runbook retire-noted, not deleted.** `docs/solutions/cross-machine/vps-dotfiles-target.md` keeps its design + Tailscale ACL block as canonical reference. Anything else (the workflow itself, the smoke script) is recoverable from git history.

## What Didn't Work

- N/A — execution was clean once the premise was clarified via AskUserQuestion. No dead ends this session.

## What's Next

1. **Nothing on the board.** No open issues, no open PRs, master is at `01890bc`. This is a clean slate — first time since the Node-24 sweep started 2026-05-11.
2. **Optional follow-up not pursued:** if you decide you want NO Linux support at all (not just no VPS sync), the further-rip targets are `install-linux.conf.yaml`, `case Linux)` in `./install`, helpers' `uname` branches, retire-noted runbook deletion. Today's scope explicitly preserved them. Bring it up only if you actually want it; not on anyone's blocker list right now.

## Gotchas & Watch-outs

- **`openclaw-prod` SSH alias still resolves**, just to a different identity. The box is now `openclaw-prod-hil` hosting Hermes + Claude Code. `claude/settings.json:133` and `.claude/settings.local.json` allowlists still permit `Bash(ssh root@openclaw-prod*)` and that's deliberate — Hermes liveness checks etc. still use it.
- **Historical docs still reference `sync-vps.yml`** — `docs/plans/2026-04-14-feat-vps-dotfiles-sync-target-plan.md`, `docs/brainstorms/2026-04-14-vps-dotfiles-target-brainstorm.md`, `docs/solutions/cross-machine/*.md` (besides the retire-noted runbook), `docs/solutions/code-quality/zsh-dash-i-c-exit-false-positive-health-check.md`. These are intentional historical archive, not stale config. Don't sweep them.
- **`HANDOFF.md` from 2026-05-20 mentioned `forge-project-key: dotfiles` was still in CLAUDE.md.** That marker is still there. Inert post-Forge-bridge-deprecation. Strip it if you want a tidier doc; harmless if you don't.
