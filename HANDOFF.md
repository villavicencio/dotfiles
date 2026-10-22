---
created_at: "2026-10-21T17:10:01-07:00"
branch: "master"
head: "96ae905"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "Report on the 2026-10-22 01:30 PT pilot run on hal (VIL-389, VIL-380, VIL-252): PRs, pass/fail, time, tokens; then close VIL-396 if it ran clean from the LaunchDaemon."
---
# HANDOFF — 2026-10-21, evening (PDT)

This session ran 2026-10-18 to 10-21 on the **hal Local Coding Pilot** (Linear P-VIL-11, runner ticket VIL-396). It built and merged the overnight runner, ran the first night (7 mergewren/dotfiles tickets), found why the local worker kept timing out, and fixed it. The LaunchDaemon is installed on hal and fires at **01:30 PT** tonight with three tickets queued. The next session's job is the morning report. Other sessions' commits since the last handoff (atlas/syd/axiom zsh commands #228/#229/#232/#234, vercel cask #230/#231, Orca setup #225) aren't covered here.

## What We Built
- **#223** — iTerm profile fonts to Light, plus the non-ASCII font.
- **#224 (`de70f7d`)** — the runner, `pilot/` (see `pilot/README.md`). Opus planner on David's claude.ai login + local `qwen3.8-27b` worker via LM Studio; gates, pre-push guard (`pilot/*` only), gitleaks on an exported copy, non-draft `[pilot]` PRs.
- **#227 (`152c372`)** — the worker writes `worker.jsonl` as it goes (stream-json), so a killed run leaves a transcript; a timed-out worker that changed files still gets its checks run.
- **#233 (`a53520e`)** — four fixes for the worker stalling, each with the evidence in `pilot/runner.py` comments and `pilot/README.md`:
  - `DISABLE_AUTO_COMPACT=1` and a 128k context cap: compaction at ~30k produced nothing for 10+ min. This is the inferred cause of all six 2026-10-18 mergewren timeouts.
  - output cap 8k → 32k: Qwen's thinking counts as output; one turn thought 9 min, hit 8k, and was reset.
  - `API_TIMEOUT_MS` 30 min, to fit a 32k turn (MergeWren `672ba32#1`).
  - `bash_rules()` appends the exact allowed Bash commands to the brief (worker was denied 14 times adding `| head`/`2>&1`). The brief in `brief.md` and the PR body now includes them (MergeWren `2fbebf3#1`).
- **#226 (`250acc8`)** — VIL-401, the first pilot PR, merged; VIL-401 Done.
- **mergewren#54 (VIL-317) and #55 (VIL-400)** — pilot PRs, merged by the mergewren session using its own procedure. **mergewren#56–#59** were empty (worker changed nothing) and closed, with their branches deleted.
- **mergewren#61 (VIL-251)** — this afternoon's test run. A real change (`post.py` +62/−15) whose three checks all pass. It's titled `[pilot][failed]` only because the worker ran out of context ("Prompt is too long") after 30 turns. **The ticket wants tests for both cases, and the worker added none**; only the planner's inline assert covers them. It needs review and mergewren's merge procedure.
- **Linear:** VIL-392's split is recorded on the ticket (item 3 corrected to the current read-to-EOF behavior), and item 2 is now **VIL-406**.

## Decisions Made
- **The worker can run code as `david`** (David's option 3, 2026-10-18). Recorded in `pilot/README.md`. Revisit OS isolation before the pilot runs past two weeks or on more repos.
- **mergewren pilot PRs are merged by the mergewren session**, never from here. In mergewren a merge is a deploy (two reviews, a suite run on the merge result, `git merge --no-ff` in the `hal` account's live folder, unit restarts). This session can't reach the `hal` account, and keeping that split is deliberate.
- **The `[pilot][failed]` title stays on a timeout or worker error** even when the checks pass. The checks table in the PR body is the signal to read.
- **Tonight's queue is limited to VIL-389, VIL-380 and VIL-252** (three per night). VIL-251 already has #61, and VIL-392 isn't for the pilot (it's mergewren review logic).

## What Didn't Work
- **The 2026-10-18 night:** 6 of 6 mergewren workers hit the 60-min limit, with no transcripts. #54/#55 still had passing changes, found by re-running the checks by hand.
- **Raising limits alone doesn't make Qwen fast.** On VIL-251 it still spent about 17 min thinking in one step. If thinking dominates tonight, try capping Qwen's thinking next (`MAX_THINKING_TOKENS` is untested against LM Studio), not raising more limits.
- **The PR relay from the Mac** (scratchpad `prs/relay.sh`) was a one-night workaround for the token's missing PR permission. The token now has Pull requests read/write, so the relay is retired.

## What's Next
1. **Morning report on the 01:30 PT run.** As `david` on hal: `~/runs/log/overnight.log`, `~/runs/log/<run>/run.json`; PRs: `gh search prs --owner villavicencio "[pilot]" --state open`. For each ticket: status, checks, turns/tokens/time. Count runs ending in "Prompt is too long" (the result event in `worker.jsonl`). If most end that way, raise `CLAUDE_CODE_MAX_CONTEXT_TOKENS` toward LM Studio's loaded 234k.
2. **Close VIL-396** once a night has run clean from the LaunchDaemon (`launchctl print system/dev.hal.pilot` shows `runs`/`last exit code`).
3. **mergewren#61 (VIL-251):** review it, add the missing tests, and merge through the mergewren session.
4. **Refill the queue.** Drop ticket files into `~/runs/queue/` on hal (format in `pilot/README.md`); `~/runs/queue/taken/` has the originals with the "Environment on hal" note. How approved tickets reach the queue automatically is VIL-397.

## Gotchas & Watch-outs
- **hal accounts:** this session reaches only `david` (ssh `david@hal`). The `hal` account (mergewren's live folder, LM Studio logs) refuses our key. `admin` needs a password, so David runs the sudo steps.
- **Never print the pilot secrets** in `~/.config/hal-pilot/` (`gh-token`, `lmstudio-token`); test with `$(cat file)` inside the remote command and print only status codes. **Never unload or reload LM Studio models** (Atlas and Axiom share both).
- **The runner only starts a ticket between 18:00 and 06:00** unless run with `--ignore-window`. A `launchctl kickstart` outside that window does nothing.
- **Running a test by hand:** `kill.sh` stops a run and creates `~/runs/DISABLED`. Always follow it with `kill.sh --on`, or the 01:30 run is skipped.
- **Reading a transcript:** `worker.jsonl` events are mostly `system/thinking_tokens` (estimated tokens per step). Distinct assistant `message.id`s are the turns; a `status: compacting` event means compaction. Output tokens read 0 for a killed worker, because LM Studio's streamed messages don't report them.
- **MergeWren on dotfiles:** a push gets an incremental round ("no verdict — incremental round; full confirmation queued"). Wait for the full confirmation before merging.
- **The worker's stderr always shows two warnings, both harmless:** "Ignoring 2 permissions.allow entries… workspace has not been trusted" (the runner passes `--allowedTools` itself) and `[claude-code:unrecognized_model]`.
