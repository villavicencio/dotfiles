---
title: tmux-attention hook blank-tab race + AskUserQuestion routing
date: 2026-04-19
category: runtime-errors
module: claude-code-tmux-attention-hook
problem_type: runtime_error
component: tooling
symptoms:
  - "Claude Code tmux tab indicator goes blank (no glyph) during AskUserQuestion long holds"
  - "PermissionRequest transitions briefly race to empty state before settling on waiting glyph"
  - "AskUserQuestion renders the generic amber warning glyph instead of a distinct question-mark icon"
root_cause: async_timing
resolution_type: code_fix
severity: medium
related_components:
  - tooling
tags:
  - claude-code-hooks
  - tmux
  - race-condition
  - async-timing
  - askuserquestion
  - bash-subshell
---

# tmux-attention hook blank-tab race + AskUserQuestion routing

## Problem

Claude Code's tmux tab indicator (`claude/hooks/tmux-attention.sh` + `tmux/tmux.display.conf`) would occasionally show a blank status (no glyph) while Claude was waiting on user input, and `AskUserQuestion` prompts were visually indistinguishable from routine tool permission prompts. The blank-tab bug was a race between the spinner's disowned background loop and the main-thread `waiting` action — both writing to the same `@claude_status` tmux user option.

## Symptoms

- Tab status blank (no glyph, no fallback `@win_glyph`) during `AskUserQuestion` prompts — visible for tens of seconds while the user reads the question.
- Brief status flicker to blank during routine `Bash` permission prompts — under 1s, usually unseen.
- `AskUserQuestion` and generic tool-permission prompts both rendered as the same amber warning glyph, no visual distinction.
- Severity scaled with how long the waiting state persisted, making the bug intermittent and easy to miss.

## What Didn't Work

- **Hypothesis: a missing `Notification` hook wire in `claude/settings.json`.** The file comment in `tmux-attention.sh` referenced `Notification` as the trigger for `waiting`, and `settings.json` had no such entry — so the obvious guess was that `AskUserQuestion` fired `Notification` and nothing caught it. **Why it failed:** theory-only, no runtime evidence. A 6-line stdin-capture diagnostic (`{ printf timestamp action pane; timeout 0.3 cat; printf separator; } >> /tmp/claude-hooks.log`) added to the top of the hook refuted it in ~30 seconds. `AskUserQuestion` actually fires `PermissionRequest` with `tool_name=AskUserQuestion` on stdin — the existing wire WAS catching it. The blank-tab symptom was downstream, in the spinner's bg loop cleanup. (Siblings the 2026-04-14 *reproduce-then-attribute* and 2026-04-16 *inspect runtime truth, don't trust docs+theory* learnings — another instance of the same anti-pattern.)

## Solution

### Part 1 — Race fix in `claude/hooks/tmux-attention.sh`

The spinner's disowned background loop (spawned via `nohup bash -c '...' &`) ran an unconditional teardown block at the end of the `bash -c` body. When the main thread serviced a `waiting` event, it removed the sentinel and wrote `@claude_status=waiting` — but the bg loop, already in `sleep 0.15`, would wake up, see the sentinel gone, exit its `while`, and run its cleanup, which unset `@claude_status` **after** the main thread had set it. The tab blanked until the next state change.

**Before (unconditional teardown races the caller):**

```bash
while [ -f "$sentinel" ] \
      && [ $i -lt $max_iterations ] \
      && kill -0 "$parent" 2>/dev/null; do
  tmux set-option -w -t "$pane" @claude_status "${frames[$((i % 6))]}" 2>/dev/null || exit 0
  i=$((i + 1))
  sleep 0.15
done
# Cleanup: restore original name and clear status.
orig=$(tmux show-options -wv -t "$pane" @win_original_name 2>/dev/null) || true
if [ -n "$orig" ]; then
  tmux rename-window -t "$pane" "$orig" 2>/dev/null
  tmux set-option -wu -t "$pane" @win_original_name 2>/dev/null || true
fi
tmux set-option -w -t "$pane" -u @claude_status 2>/dev/null \
  || tmux set-option -w -t "$pane" @claude_status "" 2>/dev/null
```

**After (cleanup gated on exit reason):**

```bash
while [ -f "$sentinel" ] \
      && [ $i -lt $max_iterations ] \
      && kill -0 "$parent" 2>/dev/null; do
  tmux set-option -w -t "$pane" @claude_status "${frames[$((i % 6))]}" 2>/dev/null || exit 0
  i=$((i + 1))
  sleep 0.15
done
# If sentinel is gone, another action is already managing state —
# exit without touching anything or we race the caller that just
# set waiting/asking (blank-icon bug).
if [ ! -f "$sentinel" ]; then
  exit 0
fi
# Parent died or max-iter cap hit — we own cleanup.
rm -f "$sentinel"
orig=$(tmux show-options -wv -t "$pane" @win_original_name 2>/dev/null) || true
if [ -n "$orig" ]; then
  tmux rename-window -t "$pane" "$orig" 2>/dev/null
  tmux set-option -wu -t "$pane" @win_original_name 2>/dev/null || true
fi
tmux set-option -w -t "$pane" -u @claude_status 2>/dev/null \
  || tmux set-option -w -t "$pane" @claude_status "" 2>/dev/null
```

### Part 2 — `asking` state in `claude/hooks/tmux-attention.sh` + `tmux/tmux.display.conf`

All `PermissionRequest` events are semantically "Claude needs me to decide" — `AskUserQuestion` prompts and ordinary tool-use confirmations (Bash, Write, etc.) have identical UX intent. So the final hook unconditionally routes every `PermissionRequest` to a single `asking` state:

```bash
waiting)
  # All PermissionRequest events are user-decision prompts (Bash
  # tool-use confirmations, AskUserQuestion, etc.) — render the
  # yellow question-mark. The legacy "waiting" action name is
  # kept to match settings.json's existing hook arg; the rendered
  # state is always "asking". If a future event (e.g. Notification,
  # if ever wired) needs the amber warning distinct from asking,
  # set state=waiting here.
  stop_spinner
  strip_leading_emoji
  set_status "asking"
  ;;
```

`tmux/tmux.display.conf` gets an `asking` branch in both format strings ahead of `waiting`, rendering U+F128 (Nerd Font Font Awesome `question-circle`) in bright yellow `#F5C300`. The literal PUA glyph was injected via a `python3` heredoc because Claude Code's Edit/Write tools strip PUA characters — see [claude-code-bash-tool-strips-pua-glyphs.md](../code-quality/claude-code-bash-tool-strips-pua-glyphs.md). The `waiting` branch stays in the ternary as reserved future state (for non-permission attention events that may get wired later); no current code path writes it.

**Design note — simpler beats specific.** An intermediate version of this fix used a `timeout 0.3 cat` stdin peek + `python3 json.load` to extract `tool_name` and only routed `AskUserQuestion` to `asking`, while generic `PermissionRequest` events kept rendering the amber warning (`waiting`). Verifying against Bash-tool-use permissions showed the distinction was UX noise — both states mean "Claude is blocked on your input." Collapsing to one `asking` state for every permission event removed ~15 lines, eliminated the stdin-peek failure mode entirely, and made the visual unambiguous.

## Why This Works

**Race fix:** ownership of `@claude_status` is now gated on exit reason. If the sentinel was removed while the loop was running, something else (the main thread servicing `waiting`, `asking`, or `clear`) is already taking over state — the bg loop exits silently and leaves that caller's write intact. Only the unplanned exits (parent PID died, 2000-iter safety cap hit) fall through to the cleanup block, which is exactly where ownership-by-worker makes sense. The pattern is generic: *requested exit → requester owns state; unplanned exit → worker owns its own cleanup*.

**Asking state:** Every `PermissionRequest` is a user-decision prompt. Whether Claude is asking a structured multi-choice question (`AskUserQuestion`) or asking permission to run a Bash command, the underlying UX is the same — the user is blocked on a choice. One visual state (yellow `\uf128`) for the whole class is clearer than two slightly-different yellows, and it eliminates the intermediate stdin-peek machinery that would have been needed to distinguish them.

The *diagnostic* stdin capture that uncovered `tool_name=AskUserQuestion` is still a reusable technique for future hook work — Claude Code writes a JSON event to each hook's stdin containing `tool_name`, `tool_input`, `session_id`, `permission_mode`, `permission_suggestions`, `transcript_path`, and more. When a future hook genuinely needs to disambiguate sub-cases of an event, `timeout 0.3 cat | python3 -c 'json.load(sys.stdin)...'` is the cheap, safe way to do it.

## Prevention

- **Background workers must gate teardown on exit reason.** If the exit was *requested* (sentinel removed, shutdown signal), the requester owns state — exit quietly. If the exit was *unplanned* (parent died, max-iter cap, unrecoverable error), the worker owns its own cleanup. Never run an unconditional teardown block in a disowned loop whose sentinel is controlled by a main-thread caller that also writes state. This applies broadly — any sentinel/shutdown pattern where a separate actor can both request shutdown *and* write state has the same race shape.
- **Diagnostic-first beats theory-first for hook / IPC / event-routing bugs.** A 6-line stdin-capture to `/tmp/*.log` refuted the "missing hook wire" hypothesis in 30 seconds. Write the probe before reasoning from docs or comments. Siblings the 2026-04-14 *reproduce-then-attribute* and 2026-04-16 *inspect runtime truth, don't trust docs+theory* learnings.
- **Hook-event stdin is the authoritative source for event detail in Claude Code.** `tool_name`, `tool_input`, `session_id`, `permission_mode`, `permission_suggestions`, `transcript_path` are all on the JSON line written to the hook's stdin. When a hook genuinely needs to disambiguate sub-cases of a single event (this bug didn't — collapsing to one `asking` state was clearer), peek stdin with `timeout 0.3 cat` and parse with `python3 -c`.
- **Prefer one state over two when the UX intent is identical.** An earlier version of this fix branched on `tool_name` to split `AskUserQuestion` (yellow `?`) from other `PermissionRequest`s (amber warning). That split had no UX payoff — both mean "Claude is blocked on your decision." Collapsing to a single `asking` state removed the stdin-peek machinery entirely and made the visual signal unambiguous.
- **File-comment drift is normal; re-derive event wiring from `settings.json` + runtime capture, not from inline comments.** The stale `Notification` reference in the hook's header is what anchored the initial misdiagnosis. Update comments aggressively when you verify behavior — or accept they'll drift and always verify from runtime.
- **When injecting Nerd Font / Font Awesome PUA glyphs into files, use `python3` heredoc or `printf` with raw UTF-8 bytes** — Claude Code's Edit/Write tools strip PUA characters. See [claude-code-bash-tool-strips-pua-glyphs.md](../code-quality/claude-code-bash-tool-strips-pua-glyphs.md) for the broader writeup.

## Related Issues

- [claude-code-hook-stdio-detach.md](../code-quality/claude-code-hook-stdio-detach.md) — prior bug in the same bg loop; this fix layers on top of its `nohup ... </dev/null >/dev/null 2>&1 &` pattern and revises the cleanup block it introduced. That doc's recipe is now incomplete — any bg loop copying its shape must ALSO gate cleanup on sentinel-still-exists, or inherit this race.
- [claude-code-notification-hook-false-positives.md](../code-quality/claude-code-notification-hook-false-positives.md) — established `PermissionRequest` as the sole attention hook in `settings.json`; this doc preserves that wiring and unifies all permission-decision prompts under the single `asking` visual state.
- [claude-code-bash-tool-strips-pua-glyphs.md](../code-quality/claude-code-bash-tool-strips-pua-glyphs.md) — load-bearing reference for why `\uf128` had to be injected via `python3` heredoc rather than written directly via Edit/Write.
- [tmux-set-option-bare-index-target-gotcha.md](../code-quality/tmux-set-option-bare-index-target-gotcha.md) — adjacent prior art on `tmux set-option` quirks.
- PR: [#39 — fix(tmux-attention): add asking state + close spinner-cleanup race](https://github.com/villavicencio/dotfiles/pull/39) (commit `3a2e1bf`)
- Historical sibling issue: `#20 Spinner replaces glyph/emoji in tmux tab while Claude is active` (closed, nearest-neighbor prior art on the tab-state family)

## Prior-session context (session history)

This hook was originally built in session `8c39177f` on 2026-04-09 (branch `tmux-claude-attention-indicator`). That session encountered several dead ends that inform this one:

- `exec -a` for process naming on macOS bash 3.2 — silently failed; replaced with `nohup bash -c CMD NAME` so the marker lands in the process's argv and `pkill -f` can find it.
- Pidfile-based pkill — only killed the registered PID; missed orphans when Claude died without firing any hook. Replaced with the current sentinel + parent-PID watch + marker-tagged process name.
- Initial `Stop`-only `clear` trigger — left the spinner frozen after permission approvals. `PostToolUse` was added as the spinner-resume trigger.

The current race (bg loop clearing state *after* the main thread set it) was **not encountered in prior sessions** — earlier iterations focused on the opposite failure mode (orphan loops running forever). The sentinel-still-exists gate is a new semantic layer on top of the existing sentinel design.

Also from session history: PUA-glyph stripping by Claude Code's Bash tool was discovered in that original hook-construction session when a Nerd Font warning-triangle (U+F071) pasted in a user message arrived empty. That observation is now captured in [claude-code-bash-tool-strips-pua-glyphs.md](../code-quality/claude-code-bash-tool-strips-pua-glyphs.md).
