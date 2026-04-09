#!/usr/bin/env bash
# Drives a per-window tmux marker so the tab in the status bar reflects
# what Claude Code is doing inside it. Three states:
#
#   waiting  -> set @claude_status=waiting (yellow warning glyph)
#   spinner  -> background loop cycling through frames, written to
#               @claude_status (orange spinner)
#   clear    -> kill any spinner, unset @claude_status (no icon)
#
# Wired up via claude/settings.json hooks:
#   UserPromptSubmit, PreToolUse              -> spinner
#   Notification, PermissionRequest           -> waiting
#   Stop                                      -> clear
#
# The spinner loop uses a sentinel file as its "keep running" signal.
# Removing the sentinel kills the loop within one frame (~150ms). This
# is more robust than pidfile tracking because:
#   - it survives lost pidfiles / leaked processes
#   - a max-runtime cap (default 600s) bounds the worst case
#   - pkill is used as a final cleanup hammer
#
# Always exits 0. Never blocks Claude Code.

set -u

action="${1:-}"
log="${TMPDIR:-/tmp}/claude-tmux-attention.log"

# No tmux, no work.
if [ -z "${TMUX_PANE:-}" ]; then
  exit 0
fi

pane="$TMUX_PANE"
pane_safe=$(printf '%s' "$pane" | tr -dc 'A-Za-z0-9')
sentinel="${TMPDIR:-/tmp}/claude-spinner-${pane_safe}.alive"
marker="claude-spinner-marker-${pane_safe}"

stop_spinner() {
  rm -f "$sentinel"
  # Nuclear cleanup: any leaked loops for this pane.
  pkill -f "$marker" 2>/dev/null || true
}

set_status() {
  tmux set-option -w -t "$pane" @claude_status "$1" 2>>"$log"
}

clear_status() {
  tmux set-option -w -t "$pane" -u @claude_status 2>>"$log" \
    || tmux set-option -w -t "$pane" @claude_status "" 2>>"$log"
}

case "$action" in
  waiting)
    stop_spinner
    set_status "waiting"
    ;;

  spinner)
    stop_spinner
    touch "$sentinel"
    # Pass marker as $0 so pkill -f can find it.
    (
      exec -a "$marker" bash -c '
        pane="$1"
        sentinel="$2"
        frames=("·" "✢" "✳" "∗" "✻" "✽")
        i=0
        max_iterations=4000  # ~10 minutes at 150ms/frame
        while [ -f "$sentinel" ] && [ $i -lt $max_iterations ]; do
          tmux set-option -w -t "$pane" @claude_status "${frames[$((i % 6))]}" 2>/dev/null || exit 0
          i=$((i + 1))
          sleep 0.15
        done
        # Loop exited (sentinel gone or timed out) — leave status as-is;
        # the hook that removed the sentinel is responsible for setting
        # the next state.
      ' "$marker" "$pane" "$sentinel"
    ) &
    disown 2>/dev/null || true
    ;;

  clear)
    stop_spinner
    clear_status
    ;;

  *)
    echo "$(date '+%Y-%m-%dT%H:%M:%S') unknown action: $action" >>"$log"
    ;;
esac

exit 0
