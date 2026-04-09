#!/usr/bin/env bash
# Re-apply window glyph + color metadata from ~/.config/tmux/window-meta.json
# to the currently running tmux server. Intended to be invoked via
#
#   set-hook -g client-attached 'run-shell "$XDG_CONFIG_HOME/tmux/scripts/restore-window-meta.sh"'
#
# Idempotent. Silently no-ops if the sidecar doesn't exist or jq is missing.

set -u

meta="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/window-meta.json"
[ -f "$meta" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Iterate every window across every session and see if we have metadata for it.
tmux list-windows -a -F '#{session_name}|#{window_index}|#{window_name}' 2>/dev/null | \
while IFS='|' read -r session idx wname; do
  entry=$(jq -c --arg s "$session" --arg w "$wname" '.[$s][$w] // empty' "$meta" 2>/dev/null) || continue
  [ -z "$entry" ] && continue

  glyph=$(jq -r '.glyph // ""' <<<"$entry")
  gcolor=$(jq -r '.glyph_color // ""' <<<"$entry")
  tcolor=$(jq -r '.title_color // ""' <<<"$entry")
  target="${session}:${idx}"

  [ -n "$glyph"  ] && tmux set-option -w -t "$target" @win_glyph "$glyph" 2>/dev/null || true
  [ -n "$gcolor" ] && tmux set-option -w -t "$target" @win_glyph_color "$gcolor" 2>/dev/null || true
  [ -n "$tcolor" ] && tmux set-option -w -t "$target" @win_title_color "$tcolor" 2>/dev/null || true
done

exit 0
