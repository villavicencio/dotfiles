# Waits

How an agent waits for something: a review, a build, another agent, a background task
(VIL-795). The one-line rule is in `claude/CLAUDE.md` and `codex/AGENTS.md`, under Subagents.
This file has the reasons.

## The rules

**Every wait has a deadline.** Give each loop a loop count or a timeout, in the foreground or
the background. When it runs out, print that it timed out and return non-zero, so a caller that
checks the exit status stops too. A loop with no end can run for hours without anyone seeing it,
and it keeps its agent alive the whole time.

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

**Review waits: use the helpers, not a loop of your own.**

- MergeWren: `source <dotfiles clone>/bin/lib/mergewren-review.sh` (on the desk Macs the clone
  is `~/Projects/Personal/dotfiles`), then `mergewren_review <pr>`. It returns 0 with the
  verdict, 1 on a GitHub error, and 2 when its deadline passes with no verdict; the other codes
  are listed at the top of that file.
- CodeRabbit, on a repo not yet on MergeWren: `cr_wait` in `docs/agents/code-review.md`,
  "Merging on a CodeRabbit review". Only status 0 can mean a review; any other status is a stop.

**Any other wait: write a loop that does all four of these.**

1. Tries a fixed number of times, or until a deadline on `$SECONDS`.
2. Succeeds only on the explicit "done" value it checks for. An empty reply, or a value it
   doesn't know, is not "done".
3. Returns non-zero when it runs out, so a caller that checks the exit status stops too.
   Printing `TIMEOUT` and exiting 0 reads as success.
4. Keeps an error apart from "not yet": it runs the status command inside an `if !`, so `set -e`
   can't exit before the error is handled, and a failure stops the loop with a fixed code of its
   own (3 below) instead of counting as pending. Don't pass the command's own code through: it
   could clash with the loop's other codes.

```bash
# wait_done <id> returns 0 done, 1 timed out, 2 unexpected reply, 3 status command failed.
wait_done() {
  local i r
  for i in $(seq 1 20); do
    if ! r=$(<status-command> "$1"); then
      echo "ERROR: the status command failed (error above)" >&2; return 3
    fi
    case $r in
      DONE) echo "done"; return 0 ;;
      PENDING) sleep 60 ;;
      *) echo "ERROR: unexpected reply '$r'" >&2; return 2 ;;
    esac
  done
  echo "TIMEOUT: not done after 20 tries" >&2; return 1
}
```

Put the real command and values in place of `<status-command>`, `DONE` and `PENDING`. The `gh`
wait example under "Polling `gh`" in `docs/agents/code-review.md` has the same shape: it is done
only on an explicit `DONE`, returns 1 on timeout, returns 2 on an unexpected reply and 3 when
`gh` fails. For a review wait, don't write a loop of either kind: use `mergewren_review` for
MergeWren or `cr_wait` for CodeRabbit.

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
