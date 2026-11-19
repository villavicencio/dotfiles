# Waits

How an agent waits for something: a review, a build, another agent, a background task
(VIL-795). The one-line rule is in `claude/CLAUDE.md` and `codex/AGENTS.md`, under Subagents.
This file has the reasons.

## The rules

**Every wait has a deadline.** Give each loop a loop count or a timeout, in the foreground or
the background. When it runs out, print that it timed out and stop. A loop with no end can run
for hours without anyone seeing it, and it keeps its agent alive the whole time.

**Tell an error from "not yet".** Check the exit status of the command you poll on every pass.
On a failure, print the error and stop. If a failure and "still pending" look the same (often
both are empty output), the loop can't tell them apart and waits on a command that will never
work.

**Never wait on another agent by reading its transcript or output file.** Wait for the
harness's notice that the agent finished. A transcript is not a status: the marker you look for
can be missing, worded differently, or outside the part you read, and then the loop never ends.

**Deal with background work before carrying on.** When the harness says work is still running
in the background (for example, when it refuses a restart), list the tasks and deal with each
one. Stop a task that won't finish with the harness's own stop (TaskStop in Claude Code), and
say that you did. If you carry on past the notice, the task keeps running and nobody looks at
it again.

## The loop shape

Use the bounded loop in `docs/agents/code-review.md`, "Polling `gh` (any reviewer, any repo)":
a fixed number of passes, a stop on any failure, and `TIMEOUT` at the end. The shape works for
any poll, not just `gh`.

## Incidents

- **dotfiles PR 259, 2026-11-02.** A MergeWren wait loop passed `--arg` to `gh`'s `--jq`.
  Every pass failed, the empty output read as "still pending", and it spun silently for about
  20 minutes until David asked.
- **eagle-hover-save, 2026-11-17 (PT).** An agent ran, in the background, `until` the last
  2,000 bytes of another agent's transcript contained a marker, `sleep 5`. The other agent
  finished at 13:42 and the marker never appeared in that window. The loop ran 5 h 09 min and
  kept its own agent alive 5.8 hours after its work was done. A `/restart` at about 15:30 was
  refused ("Can't restart while work is running in the background"), and the session carried
  on without listing the task. David found it at about 18:50; TaskStop ended it. (Epic VIL-792
  has the full table.)
