---
created_at: "2026-11-18T21:37:37-08:00"
branch: "master"
head: "cf235f3"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-11-18, evening (PT)

One long hub session in the main checkout, in Manager Mode, from the evening of 2026-11-17 to the evening of 2026-11-18 (PT). It closed the Manager Mode rollout (VIL-796) and the hal shared clone (VIL-700), filed four tickets, and did admin for the child worktree streams David ran. Nothing is in flight here: no open PRs in dotfiles or skills, the tree is clean, `master` matches origin.

## What We Built
- **VIL-796, Done.** Pointers to `dv:manager-mode` replaced the pasted copies: dotfiles PR 280 (`116c280`), obsidian-scriptorium `83974ce`, bryancola.com PR 52 (`da88e5e`), mergewren-web `998450e` (done by the MergeWren session), skills PR 65 (`4279b42`, release `dv--v0.9.1`). One done-means line is met only in part and is recorded on the ticket: the standing line made a fresh headless Sonnet session invoke the skill in 3 of 5 runs.
- **Dotfiles PR 282 (`81c6f54`).** The "Fix rounds" bullet in `docs/agents/code-review.md`: the engineer waits for the reviewer in the foreground and reports a wait that ends without a verdict. It took three rounds; the third was David's call, with the rule cut down.
- **VIL-700, Done.** `hal`'s old clone was moved aside to `dotfiles.pre-vil700` next to where it was; the undo is `restore-old-clone` in `helpers/hal_shared_clone.sh`. Closed the same evening by David's choice, skipping the runbook's one-night wait; the ticket says so.
- **Tickets filed:** VIL-808 (bryancola.com: remove retired `dv:gauntlet` from its `CLAUDE.md`), VIL-809 (Argus: tag and publish a plugin release automatically), VIL-810 (hand-off cue 200k to 500k; merged since as PR 283 by its own stream), VIL-830 (rule: the session that opens a PR moves each covered ticket to In Review; Todo, branch `docs/vil-830-in-review-rule`).
- **Linear cleanup, 2026-11-18.** 15 Dissolution stories with an open PR moved from In Progress to In Review (PRs 6 to 13 in `villavicencio/dissolution`; the list is in VIL-830's agent notes).
- **Overnight Dissolution mission.** David launched it from a prompt written here, plus an update adding authored prose and art. This session never checked its result; the 8 open PRs are from that run.
- **Memory notes** (project memory, not in the repo): `feedback_answer_is_not_a_go`, `feedback_main_session_admin_only`, `project_context_budget` (rewritten), and the mailbox paragraph in `feedback_mergewren_owns_mergewren`.

## Decisions Made
All David, by dialog or in chat, 2026-11-17 and 2026-11-18:
- **The main checkout session is admin only**: tickets, moving things, housekeeping. Dev work goes to worktree streams he starts himself. Keep the main session open while children run, if the context allows.
- **An answer to a side question is not a go.** Start ticket work only on words that start it.
- **Hand-off cue is 500k**, or 80% of a window of 500k or less. Auto-compaction is at 600k.
- **In Review rule (VIL-830):** the session that opens a PR sets each covered ticket to In Review and writes one `Refs` or `Fixes VIL-N` line per ticket in the PR description. Linear's PR link does not move status here: VIL-527 had its PR attached through the branch name and stayed In Progress.
- **bryancola.com** carries the standing Manager Mode line in its `AGENTS.md`, reversing his 2026-11-14 "memory only" choice.
- **Not decided:** a per-project `SessionStart` hook to invoke the skill deterministically. David questioned its point; no ticket was filed.

## What Didn't Work
- **The hal mailbox to the MergeWren session.** It was retired on 2026-11-17; a stale handoff and memory note said otherwise. Messages go as paste-ready text that David carries.
- **A brief that said "run the reviewer wait again if it times out"** (PR 282). MergeWren's high finding was right: a rerun resets the helper's limit. The rule now says report and stop.
- **A fresh-session test prompt that said "start no agents"** biased the result; the rerun used a neutral prompt.
- **Inferring that Linear moves tickets to In Review from the branch name.** David had moved them by hand.

## What's Next
1. **VIL-797** still reads In Review although dotfiles PRs 281 and 284 and skills PR 66 are merged. Close it, or find out what part is owed. Needs David.
2. **VIL-830**, when David starts it as a worktree stream. One step is his: read the VIL team's pull request automations in Linear; if "on PR open" is unset, turning it on does most of the job.
3. **VIL-813** (`dv:groom`) has three decisions waiting on David, per the VIL-810 stream's handoff. Also filed there and not started: VIL-812, VIL-824, VIL-825.
4. **Housekeeping for David in Orca:** Force delete the finished worktrees (`vil-761-…`, `vil-797-…`, `vil-799-…`, `vil-810-…`, `otter`).
5. **Pull hal's shared clone** to `cf235f3`, as `david` (`ssh hal`). Not checked this session whether it is current.
6. **Dissolution:** stories In Progress with no open PR found (VIL-489 to VIL-492, VIL-817, VIL-820), and VIL-519, which PR 10 names. Not looked into.
7. **Offers David has not answered** (no go given): an issue or PR to `erlhon9/orca-pod` for the hardcoded Korean topic prompt (`src/worker.ts`, `pod.suggestTopics`); a ticket for using Orca's workspace notes and unread flag as "needs you"; VIL-736 after VIL-700.
8. **Carried, still unticketed:** the Garmin MCP connection timeouts; whether Hermes on hal is up; the `compinit` fix for this Mac. Stale In Progress tickets worth a look: VIL-107, VIL-360, VIL-454.

## Gotchas & Watch-outs
- **`dv:ticket` asks for a yes on the draft before creating.** VIL-830 was filed on David's earlier "agreed" without showing the draft; he was told. Show the draft next time.
- **Read the context size, don't guess it:** the last assistant `usage` in the session transcript, or `/context`. The Orca chat UI has no statusline (VIL-798).
- **Orca children are this checkout's worktrees.** "No open worktrees" was wrong once; check `git worktree list` and Orca's child list before saying so.
- **`.claude/worktrees/vil-721-hal-memory-sections`** (detached at `a9af0f3`) belongs to another session. Leave it.
- **bryancola memory lives on hal** under account `david`; the Mac vault copies are copies. Backups from the 2026-11-17 edit sit one folder above the memory folder, suffixed `.bak-20261117`.
- **bryancola.com's main checkout on hal** was one commit behind with another session's `HANDOFF.md` change when last seen.
- **A PR that names a `VIL-` id can close it at merge.** Re-check each named ticket after a merge.
- **Pulling on hal:** pull `david`'s clone as `david`; never run git in it as `hal`.
