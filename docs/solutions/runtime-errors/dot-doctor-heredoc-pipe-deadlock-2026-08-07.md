---
title: "`dot doctor` deadlocks intermittently — bash writes a heredoc to a pipe before forking its reader"
date: 2026-08-07
category: runtime-errors
module: bin/dot
problem_type: runtime_error
component: tooling
symptoms:
  - "`dot doctor` hangs forever, printing only the first two header lines and no check results"
  - "The hung process has NO child processes and consumes no CPU"
  - "Intermittent — roughly 1 run in 8; the same command succeeds on the next attempt"
  - "`sample <pid>` parks every sample in `do_redirections → heredoc_write → write`"
root_cause: race_condition
resolution_type: refactor
severity: High
related_components:
  - development_workflow
  - verification
tags:
  - bash
  - heredoc
  - deadlock
  - pipe
  - macos
  - dot
---

# `dot doctor` heredoc deadlock

## Problem

`dot doctor` — one of the three documented verify commands — hung indefinitely, emitting only:

```
dot doctor — /Users/dvillavicencio/Projects/Personal/dotfiles
symlinks (Dotbot sources exist; installed links wired to this repo):
```

One instance sat for **1 hour 38 minutes** before being killed. Measured rate before the fix:
**1 hang in 8 runs**. That intermittency is why it went unnoticed — a retry usually works, and CI
never runs `dot doctor`.

## Root cause

Bash backs a *small* heredoc with a **pipe**, and performs redirections for a compound command
**before** executing anything inside it. So for:

```bash
if ! python3 - "$REPO/$cfg" "$REPO" "$mode" >>"$out" 2>>"$out"; then
  perr=1
fi <<'PY'
...38 lines of Python...
PY
```

bash must write all 1873 bytes into the pipe *before* forking `python3`. The only process that
would ever drain that pipe is the one bash has not created yet. If the write blocks for any
reason, it blocks **forever** — a self-deadlock with no child process to point at.

## Diagnosis trail (what actually identified it)

Ordinary debugging is misleading here, so the sequence matters:

1. **No children.** `pgrep -P <pid>` empty — so it is not waiting on an external command. That
   alone rules out the intuitive "gitleaks/brew is slow" explanation.
2. **Stack sample.** `sample <pid> 1` parked 883/883 samples in
   `do_redirections → do_redirection_internal → heredoc_write → write`.
3. **`bash -x`.** The trace stops immediately after `mode=full` with no `+ python3 …` line —
   confirming bash never reached the command, dying in the compound's redirection.

## Wrong turns — do not repeat these

- **"The heredoc is bigger than the pipe buffer."** Disproved. A sweep from 2 KB to 253 KB of
  heredoc payload never deadlocked: bash switches to a **temp file** for large documents, so big
  heredocs are *safer* than small ones. The three real heredocs here are only 475 / 1873 / 1367
  bytes.
- **"`net.local.stream.sendspace` is 8192, so >8 KB blocks."** That sysctl is for unix-domain
  sockets, not pipes. Irrelevant.
- **Isolated reproductions pass.** The same syntactic pattern — heredoc attached to an
  `if`-compound feeding `python3`, even wrapped in a function with `local` and a `for` loop —
  completes fine when run standalone. **The bug does not reproduce from the shape alone**, which
  is exactly why it reads as "works on my machine."
- **`TMPDIR` being slow or full.** Checked: writes there complete in 7 ms.

The only reliable reproduction is running the real `dot doctor` repeatedly and counting.

## Resolution

Remove heredocs from `bin/dot` entirely. The three Python bodies moved verbatim into real files:

| Was | Now |
|---|---|
| `python3 - <<'PY'` in `cmd_bench` | `bin/lib/bench.py` |
| `fi <<'PY'` in the symlinks check | `bin/lib/doctor-symlinks.py` |
| `python3 - … <<'PY'` in the docs cross-ref | `bin/lib/doctor-docs-xref.py` |

The gitleaks findings loop, which fed `$files` in via `done <<EOF`, became process substitution:

```bash
done < <(printf '%s\n' "$files")
```

Process substitution is safe where a heredoc is not: the writer is a **separate process** running
concurrently with the reader, so neither has to buffer the whole payload before the other starts.
It also preserves the original intent noted in the code — keeping the loop in the current shell so
the `real` counter survives — which a `printf | while` pipeline would break by subshelling.

`bin/dot` carries a header comment warning against inlining the helpers back.

### Verification

- Post-fix `dot doctor` output is byte-identical to a known-good pre-change run.
- **0 hangs in 20 consecutive runs**, against a 1-in-8 baseline.
- `bash -n` and `shellcheck -S warning` clean; each extracted `.py` passes `py_compile`.

## Generalisation

**Any bash heredoc feeding a command is a latent self-deadlock**, because bash writes the whole
document before the reader exists. It is invisible in review and intermittent in practice. Prefer:

- a real file for anything script-sized,
- `< <(printf …)` process substitution when the payload is in a variable,
- a heredoc only for content small enough to be obviously trivial, and never inside a loop.

Note the counter-intuitive risk profile: **small heredocs are the dangerous ones**, because large
ones get a temp file.
