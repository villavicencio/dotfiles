---
title: "Claude Code Notification hook fires on every turn-end, not just permission prompts"
date: 2026-04-08
category: code-quality
tags:
  - claude-code
  - hooks
  - notification
  - tmux
severity: Medium
component: "claude/settings.json hook config; claude/hooks/tmux-attention.sh"
symptoms:
  - A "waiting for attention" indicator (e.g., yellow warning glyph) appears after every Claude response, not just permission prompts
  - The indicator gets stuck because the Notification hook races with the Stop hook
  - Clearing the indicator on Stop doesn't help because Notification fires after Stop
problem_type: api_misunderstanding
module: claude-code-hooks
---

## Summary

The Claude Code `Notification` hook fires at the end of every turn —
including turns where Claude simply finished responding and needs no
user action. It is not limited to permission prompts or situations
requiring user attention. Using it to signal "Claude needs you" causes
persistent false positives.

## Root Cause

The `Notification` hook's semantics are broader than its name suggests.
It fires whenever Claude Code wants to notify the terminal (e.g., for
a macOS notification or bell), which includes normal turn completion.
It also races with the `Stop` hook — sometimes firing after `Stop`,
which means a cleanup action in `Stop` gets overwritten by `Notification`
setting the indicator back.

## Fix

Use `PermissionRequest` as the sole hook for "attention needed" signals.
`PermissionRequest` fires whenever Claude is blocked waiting on a user
decision — tool-call approvals (Bash, Write, etc.) and structured
user-choice prompts (`AskUserQuestion`) both arrive through this hook,
with the specific sub-case available as `tool_name` on the event's
stdin JSON. In every case it maps to the scenario where attention is
genuinely required.

```jsonc
// claude/settings.json — correct wiring
{
  "hooks": {
    "PermissionRequest": [{ "command": "~/.claude/hooks/tmux-attention.sh waiting" }],
    "Stop": [{ "command": "~/.claude/hooks/tmux-attention.sh clear" }]
  }
}
```

Do not use `Notification` for attention indicators. It is suitable for
passive signals (like a terminal bell) where false positives are harmless,
but not for stateful indicators that need explicit clearing.

## Key Takeaway

`PermissionRequest` = "Claude is blocked, user decision needed" — covers
both tool-call approvals AND `AskUserQuestion` prompts (distinguishable
by `tool_name` on the event stdin).
`Notification` = "Claude wants to ping the terminal" (fires broadly).
Only use `PermissionRequest` for attention-required indicators.
