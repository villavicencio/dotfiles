---
created_at: "2026-11-10T21:54:49-08:00"
branch: "master"
head: "6f1c9bf"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-11-10, late evening (PT)

A short session that picked up the 19:15 PT handoff. It merged the last open pilot PR in mergewren (126), sorted out what the parked mergewren work is, and handed the MergeWren session a queue. Nothing in dotfiles changed except one line of the reply layout.

## What We Built
- **mergewren PR 126 merged** (mergewren `main` at `f287575e`, 21:25 PT), through `merge-gate.sh` on hal as `hal`. The evidence is in the 2026-11-10 comment on VIL-550. The merge closed VIL-550; it is reopened to Backlog because item 3 and two low gaps remain.
- **`6f1c9bf`**: `claude/CLAUDE.md` and `codex/AGENTS.md` no longer tell agents to print a "details?" line. David read it as noise.
- **Queue sent to the MergeWren session** (SendMessage, 21:40 PT, not confirmed read): after VIL-679, PR 119 (VIL-576), PR 124 (VIL-185), PR 123 (VIL-345), then VIL-430 in the small form David set on 2026-11-03.
- **Memory** `feedback_mergewren_owns_mergewren.md`: how to identify the current MergeWren session, and how `merge-gate.sh` is used for a pilot PR.

## Decisions Made
- **PR 126 was merged, not closed** (David: go). The pilot's "Failed" label came from a bad acceptance check, `git diff --quiet --exit-code` used as "the test file changed", which fails exactly when the file changed.
- **The ten parked mergewren PRs stay parked** except the three in the queue. They are not pilot work: the MergeWren session built them with Opus in the 2026-11-04 overnight ticket run, and each stopped at that run's five-round rule. Per-PR next steps are in `~/Projects/review-stack-wt/logs/dispatch.md` on hal (account `hal`).
- **VIL-430 is un-parked** and goes to the MergeWren session. Phase A is done (recall 0.59, 0.72, 0.80 for one, two, three runs). What is left: judging the findings only the replays raised, David's spot sample of about 15, then his decision on a second run per head.
- **VIL-570 is not a pilot candidate** (my recommendation; David did not object). It has an open question, the delivery channel, and adds a scheduled job on hal. The obvious channel is an Atlas Slack DM, and Hermes on hal looks down.
- **Garmin 502s: nothing tonight.** Re-measure on 2026-11-11. If still slow, tell the health agent to call one tool at a time and retry. A Cloudflare tunnel is the last resort.
- **The Claude Duet Workflow prompt for VIL-679 was legitimate.** It came from the MergeWren session (its dispatch log: "dispatched 19:50 PST"), though Duet labelled it with this session's title. I told David to allow it; I don't know whether he did.

## What Didn't Work
- Nothing failed. One thing cost a round: PR 126's state read `OPEN` for a few seconds after `main` was pushed. Poll before deleting the branch.

## What's Next
1. **Check that the MergeWren session got the queue and that VIL-679 is moving.** `tail ~/Projects/review-stack-wt/logs/dispatch.md` over `ssh hal-orca`. If the queue is not noted there, send it again or have David paste it.
2. **Confirm the watcher reviews.** It runs (stopgap, started 19:06 PT) but has reviewed nothing since. The first PR head MergeWren pushes is the test: a verdict within about 10 minutes, or read `~/Library/Logs/mergewren-watch.log` on hal (account `hal`).
3. **When `hal` next logs in at the Mac mini's desktop without a reboot, unload the stopgap first**, or two watchers run:
   `ssh hal-orca 'launchctl bootout user/503/com.mergewren.watch; launchctl bootout user/503/com.mergewren.console'`
4. **Pilot briefs for the 01:30 PT run** were David's to pick before 22:00 PT; this session did not look at the queue. VIL-550 still carries the `hal-overnight` label, so the runner may draw from it again.
5. **Re-measure the Garmin 502s** (see Decisions).
6. **Hermes on hal looks down** (gateway and web services, checked by process name only on 11-10). David has not asked for a fix; VIL-570's channel depends on it.
7. **The seven parked PRs outside the queue** (116, 117, 118, 120, 122, 127, 129). PR 129 needs a design answer from David: its gate trusts the GitHub login, and agents share his. PRs 122 and 127 have real highs.
8. Carried over: the `compinit` fix command for this Mac, and the optional Mac items (macOS 27.2, `FileVaultMaster.keychain`, disk space).

## Gotchas & Watch-outs
- **The stopgap watcher and console are in the `user/503` launchd domain, not `gui/503`.** mergewren's documented restart (`launchctl kickstart -k gui/$(id -u)/<label>`) will not find them. The MergeWren session was told. The plist copies are in `~/.local/state/mergewren-bg-launchd/` on hal (account `hal`) and do not survive a reboot.
- **Two sessions had the title "/dv:pickup branch handoff orientation" tonight**: this one and the MergeWren session on hal. Identify the MergeWren session by its dispatch log, not its name.
- **A SendMessage to a Remote Control session reports nothing back.** Treat the queue as unconfirmed until dispatch.md shows it.
- **mergewren's full suite took 11 minutes** in the gate (3,713 tests). VIL-679 is meant to cut that; until it merges, run the gate in the background.
- **A mergewren merge closes its VIL ticket within seconds.** Re-check and reopen a multi-part one, as with VIL-550 tonight.
- **Carried over:** nothing else may use hal's local models from 01:30 to 05:00 PT; never run `npx … remote` by hand while the Desktop Commander agent is loaded; don't answer MergeWren's Slack confirmation request from David's account; old commits holding the Garmin connector address (`c01eb00`, `2542ae4`, `1a8a9ec`) are orphaned but GitHub still serves them by hash.
