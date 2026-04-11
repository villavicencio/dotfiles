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
# For emoji-in-name windows (e.g., "🦞 OpenClaw"), the leading emoji is
# temporarily stripped so the spinner/waiting glyph replaces its visual
# position. The original name is saved in @win_original_name and restored
# on clear (or when the spinner loop detects Claude has exited).
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

# Strip leading emoji from window name so the spinner/waiting glyph takes
# its visual position. Only acts if @win_original_name is NOT already set
# (idempotent across repeated spinner/waiting calls within one session).
strip_leading_emoji() {
  # Already stripped in a prior call — nothing to do.
  local orig
  orig=$(tmux show-options -wv -t "$pane" @win_original_name 2>/dev/null) || true
  [ -n "$orig" ] && return 0

  local current_name
  current_name=$(tmux display-message -p -t "$pane" '#{window_name}')

  local stripped
  stripped=$(python3 -c "
import re, sys
name = sys.argv[1]
# Standard Unicode emoji (not PUA/Nerd Font which live in @win_glyph).
# Covers emoticons, symbols, dingbats, supplemental, skin tones, ZWJ seqs.
m = re.match(r'^([\U0001F000-\U0001FFFF\u2600-\u27BF\uFE0E\uFE0F\u200D\u20E3\u2300-\u23FF\u2B50\u2B55\u00A9\u00AE]+)\s*', name)
if m:
    print(name[m.end():])
" "$current_name" 2>/dev/null)

  if [ -n "$stripped" ]; then
    tmux set-option -w -t "$pane" @win_original_name "$current_name" 2>/dev/null
    tmux rename-window -t "$pane" "$stripped" 2>/dev/null
  fi
}

# Restore the original emoji-prefixed name if we stripped it.
restore_original_name() {
  local orig
  orig=$(tmux show-options -wv -t "$pane" @win_original_name 2>/dev/null) || true
  if [ -n "$orig" ]; then
    tmux rename-window -t "$pane" "$orig" 2>/dev/null
    tmux set-option -wu -t "$pane" @win_original_name 2>/dev/null || true
  fi
}

case "$action" in
  waiting)
    stop_spinner
    strip_leading_emoji
    set_status "waiting"
    ;;

  spinner)
    stop_spinner
    strip_leading_emoji
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
      # Cleanup: restore original name and clear status.
      orig=$(tmux show-options -wv -t "$pane" @win_original_name 2>/dev/null) || true
      if [ -n "$orig" ]; then
        tmux rename-window -t "$pane" "$orig" 2>/dev/null
        tmux set-option -wu -t "$pane" @win_original_name 2>/dev/null || true
      fi
      tmux set-option -w -t "$pane" -u @claude_status 2>/dev/null \
        || tmux set-option -w -t "$pane" @claude_status "" 2>/dev/null
    ' "$marker" "$pane" "$sentinel" "$parent_pid" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
    ;;

  clear)
    stop_spinner
    restore_original_name
    clear_status
    ;;

  *)
    : # unknown action — silently ignore
    ;;
esac

exit 0
