# HANDOFF — 2026-05-20 (PDT, midday)

Light session. No repo changes from this turn — just an external-drive eject diagnostic and the standing-context refresh below. The big context shift since the last `/pickup` is commit `8f10005` (separate session, 2026-05-20 morning): **the Forge bridge in `/pickup` and `/handoff` was fully removed.**

## What We Built

- **Diagnosed why `/Volumes/1TB Media` wouldn't unmount** (off-repo). `diskutil unmount` was being dissented by PID 11949, identified via `ps -p 11949 -o pid,ppid,command` as the `browse` skill's persistent daemon (`node ... /bin/browse --session default daemon`). `lsof -p 11949` showed the daemon was cwd'd to `/Volumes/1TB Media/Gooner` — no open file handles, just the working directory pinning the volume. `kill 11949` (SIGTERM, not -9; PPID 1 = no parent to coordinate with), then `diskutil unmount /Volumes/1TB\ Media` succeeded.

- **No commits this turn.** `git log -5` shows the most recent commit on master is `8f10005` from a separate earlier-today session (see below), not this one.

## Decisions Made

- **Forge bridge is dead.** Per `8f10005` (separate session, 2026-05-20 06:33 PDT): Forge VPS half retired in the 2026-05-18 fold-and-collapse migration; Mac-side Forge as Claude Code identity survives but the SSH bridge to `openclaw-prod` is gone. Both `/pickup` (Step 2c) and `/handoff` (Steps 5+6) had Forge logic removed. **Durable learnings now live in `~/.claude/projects/<repo-slug>/memory/` and `HANDOFF.md` only** — no more `_shared/patterns.md` or cadence-log appends.
- **Project CLAUDE.md still says `forge-project-key: dotfiles`** at the bottom. The corresponding marker was already removed from the `openclaw` repo (per `villavicencio/openclaw@4428249`). Whether to also strip this dotfiles marker is an open question — it's vestigial but harmless. Did not touch it this session.

## What Didn't Work

- Nothing tried-and-failed this turn. The drive-unmount diagnostic worked first try once the holder was identified.

## What's Next

1. **#79 still open** — `vps: /root/.dotfiles missing on openclaw-prod — sync-vps.yml broken`. Sync VPS workflow remains broken end-to-end until the VPS-side directory is restored or the workflow decommissioned. Three options documented in the ticket body. Carry-forward from 2026-05-17 handoff; user has not yet picked a path.
2. **Optional cleanup:** strip `forge-project-key: dotfiles` from project CLAUDE.md if you want the marker gone everywhere. Low-priority — it's an inert label now.
3. **`browse` daemon cwd-pinning is a recurring footgun.** If you keep hitting this with external drives, consider always launching `browse` from `cd ~` first. Optional defensive measure, not blocking anything.

## Gotchas & Watch-outs

- **The Forge bridge in slash commands is gone, but local memory is the new home.** Next session: don't expect Forge cadence to be there. Write learnings to memory or HANDOFF.md.
- **`browse` daemon detaches to PPID 1.** It survives shell exits and won't be reaped — if you need to recover it, `pgrep -f "browse.*daemon"` finds it cleanly. Plain `kill` is sufficient (designed restartable).
- **Sync VPS workflow still broken** — #79 unresolved. Don't run it expecting success.
