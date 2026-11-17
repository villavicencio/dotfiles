---
created_at: "2026-11-17T12:19:21-08:00"
branch: "master"
head: "c8cefce"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "VIL-761 (David asked to look at it in a fresh session); VIL-700 waits one night, then verify and retire-old-clone tomorrow outside 01:30-06:00 PT"
---
# HANDOFF — 2026-11-17, midday (PT)

A session from the evening of 2026-11-16 to midday 2026-11-17, in Manager Mode. VIL-700 part 2 (one shared dotfiles clone on hal) was built, reviewed, merged and run on hal, with one regression found and fixed on the way. Alongside it the session bootstrapped a new project, Eagle Hover Save, and set up a mailbox so dotfiles sessions can reach the MergeWren session.

## What We Built
- **PR #273** (`c817d86`), VIL-700 part 2: `helpers/hal_shared_clone_sync.sh` (step 1, from the Mac), `helpers/hal_shared_clone.sh` (steps and rollbacks on hal), `helpers/hal_dotfiles_sync_check.sh` (Atlas's new hourly check with the tamper alarm), `ci/hal-shared-clone-checks.sh`. Run order and recovery: `docs/reference/install-and-server.md`, "One dotfiles clone on hal". Five fix rounds; three mediums declined, reasons in the PR body.
- **PR #274** (`c8cefce`): `zsh/functions.sh` loads function files with case-sensitive globbing scoped to the loader, so it works through a search-only home folder; `verify` now proves the loader works for `hal` without writing anything. This file runs on this Mac too: same functions, startup about 200 ms.
- **hal, done 2026-11-17 10:23–12:19 PT:** both clones on `c8cefce`; `david`'s home has `user:hal allow search`, with `~/.claude/file-history`, `~/.claude/shell-snapshots`, `~/scratch` at 700 and `~/env.sh` at 600 (old modes in `~/.vil-700-modes-before-acl`); the new hourly check installed (old one kept as `.pre-vil700`); `hal`'s 24 links and `~/.claude/CLAUDE.md` point into `david`'s clone; `verify` exits 0. Full record in the VIL-700 comments.
- **Eagle Hover Save** (new project, `~/Projects/eagle-hover-save`, private repo `villavicencio/eagle-hover-save`): bootstrap, Orca registration, vault, upstream baseline doc. Its own `HANDOFF.md` carries everything; continue there in a session of its own, not here.
- **MergeWren mailbox:** `/Users/hal/agent-mail/mergewren/` (account `hal`), reached with `ssh hal-as-hal`. Round trip tested. How to use it: memory file `feedback_mergewren_owns_mergewren.md`.
- **Linear:** VIL-779 (MergeWren onboarding for eagle-hover-save, being worked by MergeWren), VIL-780 (`dv:new-project` skill idea, Argus project), VIL-736 comment (`dot` as `hal` will fail after the move; nothing unattended uses it).
- **Memory:** `feedback_interview_even_with_background_work.md` (David keeps multiple-choice dialogs even when they hold background work, unless he calls a run autonomous).

## Decisions Made
- **David, 2026-11-16:** close the four paths above before letting `hal` through `david`'s home.
- **David, 2026-11-17:** leave the other folders in `david`'s `~/Projects` (axiom, hermes, hal-pilot, hal-bench, skills, browse-gateway, bryancola.com, bryancola-backups) readable to `hal`. He was shown they become readable.
- **David, 2026-11-17:** keep the multiple-choice question format; declined a proposal to put decisions in the reply while background work runs.
- **Eagle Hover Save, David 2026-11-17:** track a pristine `upstream/` that MergeWren skips; customization in `src/` plus `patches/`; the import PR carries the fetch-and-verify script so it gets a real verdict; an agent drives the drag check.
- The hal steps were run by the manager session directly (existing scripts, David's go given at the start of part 2), not by a lead.

## What Didn't Work
- **The first relink (10:28 PT).** `verify` passed, but every interactive zsh as `hal` lost its functions: `NO_CASE_GLOB` makes zsh read every folder on an absolute glob path, and `hal` may search `david`'s home but not read it. Caught by the manual startup check in the run order, rolled back in about a minute. Fixed by PR #274.
- **SendMessage to the MergeWren session.** Neither session can tell which listed peer is the other; the mailbox replaced it.
- **The memory index line** for MergeWren still pointed at a dead tmux pane; corrected. Read the full memory file, not the index line, before reaching MergeWren.
- **A question dialog left open overnight** held the session from ~21:00 to 07:59 PT, so PR #273 sat unreviewed. David accepts that cost.

## What's Next
1. **VIL-761** (Backlog): adopt the manager-mode prompt into dotfiles and maintain it there. David asked to look at it in a fresh session. The prompt today lives in memory, `feedback_manager_mode_sop.md`.
2. **VIL-700, tomorrow 2026-11-18, outside 01:30–06:00 PT and 18:00 PT:**
   - Atlas's job status: `ssh hal-as-hal '/opt/homebrew/bin/jq ".jobs[] | select(.id==\"637debb93470\") | {last_status, last_error, failure_streak, last_run_at}" ~/.hermes/cron/jobs.json'` → `last_status: "ok"`, `failure_streak: 0`. Also any Slack DM from the check overnight.
   - `ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh verify'` → exit 0.
   - Optional inventory, then `retire-old-clone` (dry run first). It moves `hal`'s old clone to `~/Projects/Personal/dotfiles.pre-vil700`; never deleted. Then mark VIL-700 Done.
3. **Owed doc:** the MergeWren mailbox in `docs/agents/code-review.md` (through a lead; the memory file has the text).
4. **VIL-736** (Todo, Low), after VIL-700.
5. **Carried, still unticketed:** the Garmin 502s; whether Hermes on hal is up; the MergeWren stopgap watcher after hal's reboot on 2026-11-11 (the watcher was running today); the `compinit` fix for this Mac.

## Gotchas & Watch-outs
- **Pulling on hal from now on:** pull `david`'s clone as `david` (`ssh hal`). Never run git in it as `hal`, and never give `hal` a `safe.directory` entry. A merge that changes `helpers/hal_dotfiles_sync_check.sh` needs step 3 (`sync-check`) re-run as `hal`; Atlas's report says so.
- **The overnight pilot runs as `david` and can write files `hal` runs.** The hourly tamper alarm detects a change within an hour; it doesn't prevent one. That was David's accepted trade-off.
- **Rollback if hal misbehaves:** `ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh relink-rollback'`. Full order: the docs section above.
- **Every VIL-700 PR merge auto-closes the ticket** (title or branch names it). It was reopened twice today; re-check after any further merge.
- **Another session is active:** PR #276 (`docs/mergewren-base-wt-hal-orca-rm`, worktree `.claude/worktrees/mergewren-base-wt-hal-orca-rm`) and the merged #275 are not this session's. The `vil-721-hal-memory-sections` worktree also belongs to another session; leave both.
- **macOS CI legs** sometimes get cancelled before a runner is assigned (no steps run, ~15 min). `gh run rerun <run> --failed` fixed it on #274.
- **Lead reports arrive HTML-escaped** (`&amp;`, `&lt;`). Never copy a command for David out of one.
- **Eagle Hover Save** has its own open items (MergeWren adoption VIL-779 not live yet; MergeWren's answer on a verdict for a mostly-skipped import PR pending in its outbox). They belong to that project's session.
