---
created_at: "2026-11-03T07:33:36-08:00"
branch: "master"
head: "8705bb7"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "check the 2026-11-03 01:30 PST hal pilot run (VIL-546, VIL-544, VIL-550 briefs), not yet looked at; reopen partial tickets after merges; pick tonight's briefs before 22:00 PT"
---
# HANDOFF — 2026-11-03, morning (PST)

This session picked up the 11-02 evening handoff (`8defc50`) and, on David's word, did VIL-579, rotating the Desktop Commander remote's LaunchAgent log. It took seven MergeWren rounds and merged as #259. It then wrote down two review-loop lessons and answered what survives an Orca restart or reboot. Nobody has looked at last night's 01:30 PST pilot run yet.

## What We Built
- **#259** (`31c67a9`, VIL-579 Done): rotation in `helpers/desktop_commander_remote.sh` (`rotate_log`, `rotate_log_if_due`, a watcher check every `WATCH_SECS`, exit code `LOG_MOVED=11` → job exits 1 so launchd restarts it). Hand-run check: `ci/desktop-commander-remote-log-checks.sh` (macOS only; 30 unit cases under `/bin/bash` 3.2 plus a full-job run against a fake package). Policy and failure behavior are in `docs/reference/tooling.md` under "The log rotates itself (VIL-579)". **Not live until David re-runs the installer** (What's Next 1).
- `3655537`, in `docs/agents/code-review.md` "Polling `gh`": `gh --jq` takes no `--arg`, and wait loops must check `gh`'s exit status. A silent infinite poll on #259 cost a round of waiting.
- `c6308a2` (`docs/reference/review-and-merge.md`): MergeWren's `no verdict … full confirmation queued` comment isn't a result. A full review follows and can raise new findings. Superseded in practice by #260's `mergewren_review` (`88e9774`, another session's).
- `8705bb7` (`docs/reference/orca-worktrees.md`, "What survives an Orca restart or update, and a reboot"):
  - Orca terminals run under a separate `Orca Terminal Host` that launchd starts, so an app restart or update keeps every local session running.
  - A Mac reboot ends them; the conversations can be resumed.
  - Atlas and Axiom run in tmux on hal, so neither touches them.

## Decisions Made
- **Copy-then-truncate, not `newsyslog`:** launchd opens the log O_APPEND. macOS `newsyslog` has no copy-truncate flag, and renaming the file would leave the job writing to the renamed copy.
- **Identity check before every rotation:** the job compares the device:inode of its stdout (`lsof`) with the path's (`/usr/bin/stat`, no `-L`). A symlink or a replaced file is never truncated. A mismatch at start-up disables rotation for that run; one found by the watcher triggers a restart.
- **Declined MergeWren `0b082d5#1`/`#2` (gap recorded in #259's body and on VIL-579):** if launchd recreates the log and `lsof` fails at that same start-up, that run skips `chmod 600`. The fix, if wanted, is to chmod on the lsof-failure branch too.
- **The `gh --jq` lesson went into dotfiles `docs/agents/`, not this repo's reference docs**, because it applies to every repo (David agreed).

## What Didn't Work
- `gh pr view --jq '…' --arg h <sha>` fails with "accepts at most 1 arg(s), received 4". In a loop without an exit check it spins silently. Splice the value into the filter, or pipe to real `jq`.
- A wait loop that matched any `review-stack:head=<sha>` comment would also match the "no verdict" placeholder, or wait forever on it. Use `mergewren_review <N>` (#260) now.
- `stat /dev/fd/1` on macOS returns a devfs node, not the log file. Use `lsof -a -p $$ -d 1 -F Di` (≈26 ms).

## What's Next
1. **David, in a terminal on the Mac (not through Desktop Commander):** `bash ~/Projects/Personal/dotfiles/helpers/install_desktop_commander_remote.sh`. This activates the #259 rotation and restarts the remote for a few seconds.
2. **Check the 11-03 01:30 PST pilot run:** `ssh hal` (as `david`), `tail ~/runs/log/runner.log`, then `~/runs/log/vil-54{6,4}-*/run.json` and `vil-550-*/run.json`. Hand passing PRs to MergeWren with the evidence.
3. **After any pilot merge, reopen the parent ticket** (VIL-546, VIL-544, VIL-550): each brief covered only part of it (VIL-543).
4. **Before 22:00 PT tonight, pick the next night's briefs** from the `hal-overnight` label, checking each on current mergewren `main` in a scratch clone.
5. **David, in the MergeWren session:** mergewren#105 (VIL-448) and mergewren#103 (VIL-345), both carried over.
6. Backlog: VIL-552/553/554 (hal-pilot), VIL-581 (remote QA, needs David at the Mac), and optionally the declined chmod gap above.

## Gotchas & Watch-outs
- **Agent shells have GNU `stat` first on PATH.** Rotation code and its tests use `/usr/bin/stat`; the job itself runs under launchd's `/bin/bash` 3.2.
- **`--remove` leaves the logs behind:** `~/Library/Logs/desktop-commander-remote.log*` and the package's day logs in `~/.desktop-commander-device/`. Deleting them is David's call.
- **Another session's worktree:** `.claude/worktrees/mergewren-review` on `feat/mergewren-review`. Leave it alone; #260 merged from that work, so it may be ready for `wt done` by its own session.
- **A lingering Orca Terminal Host from 2026-10-18 (pid 75675) has no shells.** It's harmless, and logout clears it.
- **Carried over:**
  - Never run `npx … remote` by hand while the agent is loaded.
  - Never run the installer or `--remove` through Desktop Commander.
  - Nothing else runs on hal's local models 01:30–05:00 PST.
  - MergeWren gates pilot merges on David's own per-PR approval; don't relay approvals.
