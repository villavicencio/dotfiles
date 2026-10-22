---
created_at: "2026-10-22T10:37:42-07:00"
branch: "master"
head: "156def1"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "Morning report on the 2026-10-23 01:30 PT pilot run on hal (VIL-391, VIL-417, VIL-381): status, checks, time split with pilot/timing.py, tokens; and whether any run hit the 60-min limit vs \"Prompt is too long\""
---
# HANDOFF — 2026-10-22, morning (PDT)

This session picked up the hal Local Coding Pilot (Linear P-VIL-11) after its first LaunchDaemon night. It reported the 2026-10-22 01:30 PT run, raised the worker's context cap because running out of context was the main failure, reran VIL-380 (which then passed), and queued three tickets for the 2026-10-23 01:30 PT run. The next session's job is that morning's report. Other sessions' commits since the last handoff (Orca cleanup #236, herdr #235, obsidian #237, docs) aren't covered here.

## What We Built
- **First LaunchDaemon night (2026-10-22 01:30–02:52 PT):** VIL-389 passed (mergewren#69). VIL-380 failed, out of context (mergewren#71, since closed). VIL-252 was declined (it leaves decisions to David). Results are in a comment on **VIL-396**, which is now **Done**.
- **#238 (`54c4353`):** the worker's context cap went from 128k to 192k (`CLAUDE_CODE_MAX_CONTEXT_TOKENS=196608` in `pilot/runner.py`), and `pilot/plan-prompt.md` now tells the planner 192k (MergeWren `05764ee#1`). Both failed runs had stopped near 109k; LM Studio has `qwen3.8-27b` loaded with 233,984 tokens of context, and the prompt shares that with the 32k reply.
- **VIL-380 rerun by hand (03:47–04:41 PT):** it passed (**mergewren#73**), peaked at 145k of context, and used 51.2 of its 60 minutes. mergewren#71 was closed as superseded, and its branch deleted.
- **#239 (open, `feat/pilot-timing`):** `pilot/timing.py` splits a run's `worker.jsonl` into thinking, tool and other time. Thinking was 54–72% of worker time on all four transcripts, and the longest single think was 15.7 min. Tested on hal; the path for a stopped worker (no `result` event) is untested because no such transcript exists yet.
- **`30f4e5f` (master):** `pilot/README.md` "The queue" now records which tickets fit the pilot, and that the queue runs in file-time order.
- **Queue for 2026-10-23 01:30 PT** (`~/runs/queue/` on hal, runs in this order): `09-vil-391.md`, `10-vil-417.md` (item 4: remove the dead code), `11-vil-381.md` (most likely to hit the 60-min limit; the file names a smaller fallback). All three are in mergewren. Each carries the "Environment on hal" note.
- **Linear:** new label `hal-overnight` on VIL-391, VIL-417 and VIL-381, marking tickets David approved for the pilot.

## Decisions Made
- **MergeWren does all mergewren work** (David, 2026-10-22: "I prefer if MergeWren works on MergeWren"): fixes as well as merges, pilot PRs included. This session reports on runs and hands PRs over with SendMessage (session "VIL-317 and VIL-400 pilot merges"); it doesn't edit mergewren branches. Saved to memory (`feedback_mergewren_owns_mergewren.md`).
- **VIL-397 (automatic ticket intake) is deferred.** The bottleneck is merging, not picking tickets, and the worker's settings are still changing. Pick it up once merges keep up with incoming PRs, a week of runs has gone without a settings change, and VIL-398's two-week verdict says keep going. Until then: hand-pick tickets, copy them into the queue, and add the `hal-overnight` label.
- **The 60-minute worker limit stays** until a run actually times out. If one does, raising it is the next change, not the context cap. David is fine with runs going past 06:00 PT.
- **Running past 06:00 by hand is fine:** `runner.py --once --ignore-window` under `nohup` as `david`.

## What Didn't Work
- **Adding up `system/thinking_tokens` events** gives nonsense: each is a running estimate for its step. Use `thinking_duration_ms` on assistant events (what `pilot/timing.py` does).
- **Obscura and bryancola.com tickets don't fit the pilot yet.** Most Obscura tickets leave a design question open, so the planner would decline them, and bryancola's checks need the network. VIL-126 part C (a one-line sizing-message fix) is the one small Obscura task worth queueing if it's scoped to that part alone.

## What's Next
1. **Morning report on the 2026-10-23 01:30 PT run.** As `david` on hal: `~/runs/log/runner.log` (the LaunchDaemon's log; `overnight.log` holds only older runs), then `~/runs/log/<run>/run.json` for each ticket. Run `pilot/timing.py ~/runs/log/<run>/` for the time split (from the clone if #239 has merged, or copy the script from that branch). For each run, say whether it ended done, on "Prompt is too long", or stopped at the time limit (`killed` set in `run.json`).
2. **#239:** wait for MergeWren's review of the current head (its watcher may still be stopped, see Gotchas), fix any findings, then merge and delete the branch. On merge, `git pull` hal's clone.
3. **Pilot PRs waiting on the MergeWren session:** mergewren#61 (VIL-251, a high finding plus missing tests), #73 (VIL-380, a medium docs finding) and #69 (VIL-389, clean). Tonight's three PRs will join them. David's part: clear the VIL-423 lock and give that session his go-ahead to merge pilot PRs.
4. **Refill the queue for the next night**, using the rules in `pilot/README.md` "The queue".

## Gotchas & Watch-outs
- **MergeWren's watcher was halted** by a fake incident lock that a test wrote into the live lane (**VIL-423**). Only David can clear it. Until he does, no MergeWren review runs on any repo, including this one (#239).
- **Mentioning a VIL id in a PR title or body can auto-close it on merge** (global CLAUDE.md). #238 named VIL-380 and VIL-251 and didn't close them, but check after every merge.
- **The queue runs oldest file first by modification time, not by name.** Copy files in the order you want them run.
- **`sed` is BSD in agent shells** (it isn't coreutils, so `zshenv`'s `gnubin` doesn't cover it). CLAUDE.md's "Paths" section now says so. Use `sed -i ''`, `gsed`, or the Edit tool.
- **hal accounts:** this session reaches only `david@hal`. The MergeWren session runs as `hal`. Never print anything from `~/.config/hal-pilot/`, and never load or unload LM Studio models.
- **The `opaleye` Orca worktree is already gone** (removed outside this session); nothing to clean up.
