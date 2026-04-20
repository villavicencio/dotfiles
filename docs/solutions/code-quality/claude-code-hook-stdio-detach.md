---
title: "Claude Code hooks freeze UI if background processes inherit stdio"
date: 2026-04-08
category: code-quality
tags:
  - claude-code
  - hooks
  - background-process
  - stdio
  - tmux
severity: High
component: "claude/hooks/tmux-attention.sh; claude/settings.json hook config"
symptoms:
  - Claude Code UI hangs on every tool call
  - Claude Code becomes unresponsive after a hook fires
  - Killing the background spinner process unblocks Claude
  - The hang only occurs when a hook launches a backgrounded subprocess
problem_type: resource_contention
module: claude-code-hooks
---

## Summary

When a Claude Code hook (`PreToolUse`, `PostToolUse`, etc.) launches a
background process, that process inherits the hook's stdout and stderr
file descriptors. Claude Code's hook runner reads from these pipes and
waits for EOF before continuing. A long-running background process (like
a spinner loop) holds the pipe open indefinitely, blocking Claude's UI
on every subsequent tool call.

## Root Cause

Standard `cmd &` in bash backgrounds the process but does not close
inherited file descriptors. The backgrounded process keeps the hook's
stdout/stderr pipes open. Claude Code's hook runner waits for all
output on those pipes to complete before returning control to the UI.
Result: the UI freezes until the background process exits or the pipes
are manually closed.

## Fix

Fully detach all stdio when backgrounding any process from a hook:

```bash
nohup bash -c '
  # your long-running work here
' </dev/null >/dev/null 2>&1 &
```

All three redirections are required:
- `</dev/null` — detach stdin (prevents blocking on read)
- `>/dev/null` — detach stdout (prevents holding the hook's output pipe)
- `2>&1` — detach stderr (same issue as stdout)
- `nohup` — survive the hook's shell exiting
- `&` — background the process

Omitting any of the output redirections will cause the freeze.

## Key Takeaway

Every background process launched from a Claude Code hook must use the
full `</dev/null >/dev/null 2>&1 &` detach pattern. This is not optional
— even a process that produces no output still holds the pipe open by
virtue of having the file descriptor inherited.

## See Also

If your backgrounded loop uses a sentinel file for shutdown control AND
a main-thread caller can remove that sentinel while also writing state,
the detach pattern above is necessary but not sufficient — an
unconditional cleanup block at the end of the loop will race the
caller's write and produce a blank / stale state. Gate the cleanup on
exit reason (sentinel-still-exists = "unplanned exit, worker owns
cleanup" vs sentinel-gone = "requested exit, caller owns state") to
close the race. See
[tmux-attention hook blank-tab race + AskUserQuestion routing](../runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md)
for the full analysis and the fix pattern.
