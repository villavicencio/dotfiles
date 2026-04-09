#!/usr/bin/env bash
# Toggle a per-window tmux marker so the tab in the status bar can light up
# when Claude Code needs the user's attention.
#
# Wired up via claude/settings.json hooks:
#   Notification, PermissionRequest, Stop  -> set
#   UserPromptSubmit                       -> clear
#
# The marker is a window-scoped tmux user option (@claude_status). The
# tmux window-status-format reads it via a ternary and prepends an icon.
#
# Always exits 0 — this hook must never block Claude Code.

set -u

action="${1:-}"
log="${TMPDIR:-/tmp}/claude-tmux-attention.log"

# No tmux, no work.
if [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

case "$action" in
  set)
    tmux set-option -w -t "$TMUX_PANE" @claude_status waiting 2>>"$log"
    ;;
  clear)
    tmux set-option -w -t "$TMUX_PANE" -u @claude_status 2>>"$log" \
      || tmux set-option -w -t "$TMUX_PANE" @claude_status "" 2>>"$log"
    ;;
  *)
    echo "$(date '+%Y-%m-%dT%H:%M:%S') unknown action: $action" >>"$log"
    ;;
esac

exit 0
