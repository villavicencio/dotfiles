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
  tmux set-option -w -t "$pane" @claude_status "$1" 2>/dev/null
}

clear_status() {
  tmux set-option -w -t "$pane" -u @claude_status 2>/dev/null \
    || tmux set-option -w -t "$pane" @claude_status "" 2>/dev/null
}

case "$action" in
  waiting)
    stop_spinner
    set_status "waiting"
    ;;

  spinner)
    stop_spinner
    touch "$sentinel"
    # Capture parent PID — Claude Code spawns hooks directly, so $PPID
    # is the Claude Code process. The loop watches it and self-exits
    # if Claude dies (no SessionEnd hook exists).
    parent_pid=$PPID
    # Background the loop. CRITICAL: redirect stdin/stdout/stderr to
    # /dev/null so we don't hold open the hook's pipe — otherwise
    # Claude Code blocks waiting for the pipe to close.
    # Marker is passed as $0 of the inner bash via `bash -c CMD NAME`
    # so pkill -f can find leaked loops.
    nohup bash -c '
      pane="$1"
      sentinel="$2"
      parent="$3"
      frames=("·" "✢" "✳" "∗" "✻" "✽")
      i=0
      max_iterations=2000  # ~5 minutes at 150ms/frame (safety net)
      while [ -f "$sentinel" ] \
            && [ $i -lt $max_iterations ] \
            && kill -0 "$parent" 2>/dev/null; do
        tmux set-option -w -t "$pane" @claude_status "${frames[$((i % 6))]}" 2>/dev/null || exit 0
        i=$((i + 1))
        sleep 0.15
      done
      # If we exited because the parent died, clear the status so the
      # tab does not stay frozen on the last frame.
      if ! kill -0 "$parent" 2>/dev/null; then
        tmux set-option -w -t "$pane" -u @claude_status 2>/dev/null \
          || tmux set-option -w -t "$pane" @claude_status "" 2>/dev/null
      fi
    ' "$marker" "$pane" "$sentinel" "$parent_pid" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    ;;

  clear)
    stop_spinner
    clear_status
    ;;

  *)
    : # unknown action — silently ignore
    ;;
esac

exit 0
