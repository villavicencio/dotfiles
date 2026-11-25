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

**Reading a command's exit code: the `if !` trap.** Don't write
`if ! cmd; then rc=$?; …; fi`. Inside that `then`, `$?` is the status of the negated test, which
is 0, not the status of `cmd`. So `rc` is always 0, and the loop can't tell an error from "still
running". To keep the command's own code, use `rc=0; cmd || rc=$?`, which is also safe under
`set -e`:

```bash
rc=0; r=$(<status-command> "$1") || rc=$?
if [ "$rc" -ne 0 ]; then echo "ERROR: status command failed (exit $rc)" >&2; return 3; fi
```

Running `cmd` on its own line and reading `rc=$?` on the next is not the fix: under `set -e` the
script exits at `cmd` before `rc` is read. The `wait_done` loop above is fine, because it never
reads `$?` inside `if !`; it returns its own fixed 3.

## Waits longer than 2 hours

Claude Code's Bash tool caps a background command's `timeout` at 7200000 ms (2 h). The default
is 1800000 ms, and a foreground command is capped at 600000 ms. A larger value is clamped to the
cap silently, and at the limit the task is stopped and the agent is re-invoked. So a wait that
must outlast 2 h can't be one long timeout.

Keep the overall deadline yourself, as an absolute time in a file, and run bounded waits of
under 2 h each. When one ends, read its exit status and the clock: re-arm the next wait if the
deadline hasn't passed, otherwise stop with a timeout and return non-zero. Have each wait end
itself a little before the cap (7000 s below), so it exits with its own code instead of being
stopped.

```bash
# Once, before the first chunk: the overall deadline (here 8 h from now) and the function file.
echo $(( $(date +%s) + 8*3600 )) > <deadline-file>
cat > <wait-chunk-file> <<'EOF'
# wait_chunk <id> <deadline-file> returns 0 done, 1 overall deadline passed, 2 unexpected reply,
# 3 status command failed or bad deadline file, 4 this chunk is over and the deadline has not
# passed: run it again.
wait_chunk() {
  local r now nap deadline chunk_end
  deadline=$(cat "$2" 2>/dev/null)
  case $deadline in
    ''|*[!0-9]*) echo "ERROR: no valid deadline in '$2'" >&2; return 3 ;;
  esac
  chunk_end=$(( $(date +%s) + 7000 ))
  while :; do
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then echo "TIMEOUT: overall deadline passed" >&2; return 1; fi
    if [ "$now" -ge "$chunk_end" ]; then return 4; fi
    if ! r=$(<status-command> "$1"); then
      echo "ERROR: the status command failed (error above)" >&2; return 3
    fi
    case $r in
      DONE) echo "done"; return 0 ;;
      PENDING) ;;
      *) echo "ERROR: unexpected reply '$r'" >&2; return 2 ;;
    esac
    nap=$(( deadline - $(date +%s) ))
    if [ "$nap" -gt 60 ]; then nap=60; fi
    if [ "$nap" -gt 0 ]; then sleep "$nap"; fi
  done
}
EOF
```

Each chunk is a new background Bash call, a fresh shell with none of the earlier definitions, so
it sources the function file and runs `wait_chunk` itself:

```bash
source <wait-chunk-file> || exit 3
rc=0; wait_chunk <id> <deadline-file> || rc=$?
echo "wait_chunk exit $rc"
exit "$rc"
```

Give each chunk call a `timeout` of 7200000 or less. The call exits with `wait_chunk`'s code, and
prints it too once the function file has sourced: 0 is done, 1 is deadline passed, 2 and 3 are
errors (3 also when the deadline file is bad or the function file won't source), and 4 is a
normal chunk end, so start the next chunk. The block captures the code with `|| rc=$?`, so a 4
doesn't end a `set -e` shell before the `echo` and `exit`. Any code outside 0 to 4 means the
chunk was stopped from outside (the cap, a signal): check the clock against the deadline before
you start another.

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
- **Two waits, 2026-11-20.** A background wait asked for a timeout of 18,600,000 ms; Claude Code
  clamped it to the 2 h cap, so it ended after 2 h instead of lasting the night. A wait loop
  read `rc=$?` inside `if !`, got 0 on every pass, and couldn't tell an error from "still
  running".
