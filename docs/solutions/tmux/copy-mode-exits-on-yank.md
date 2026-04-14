---
problem_type: UX keybinding default
severity: medium
module: tmux/copy-mode
tags: [copy-mode-vi, yank, scroll-position, keybinding]
date_resolved: 2026-04-10
---

# tmux copy mode exits on yank, losing scroll position

## Symptom

In copy mode (scrolled up reading output), selecting text and yanking
with `y` or mouse drag exits copy mode and snaps the view back to the
bottom of the pane. The user loses their place and must scroll back up.

## Root Cause

tmux's default vi copy-mode bindings use `copy-selection-and-cancel`,
which copies the selection AND exits copy mode. This differs from Vim
where yanking in visual mode keeps you in the buffer.

## Fix

Bind `y` and `MouseDragEnd1Pane` to `copy-selection` (without
`-and-cancel`) in `tmux/tmux.general.conf`:

```tmux
# Stay in copy mode after yanking (don't jump back to the bottom)
bind -T copy-mode-vi y send-keys -X copy-selection
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection
```

Exit copy mode explicitly with `q` or `Escape` when done.

## Verification

1. Enter copy mode: `Prefix + [`
2. Scroll up with `Ctrl-u` or `k`
3. Select text: `Space` → move → `y`
4. Confirm: still in copy mode, same scroll position
5. `q` to exit — view snaps to bottom
