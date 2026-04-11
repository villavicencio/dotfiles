#!/usr/bin/env bash
# Persist a window's glyph + color metadata to ~/.config/tmux/window-meta.json.
#
# Usage:
#   save-window-meta.sh <session> <window_name> <glyph> <glyph_color>
#
# Writes atomically via a temp file + mv. Requires jq.

set -euo pipefail

meta="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/window-meta.json"
mkdir -p "$(dirname "$meta")"
[ -f "$meta" ] || echo '{}' > "$meta"

if ! command -v jq >/dev/null 2>&1; then
  echo "save-window-meta: jq is required but not installed" >&2
  exit 1
fi

session="${1:-}"
window="${2:-}"
glyph="${3:-}"
glyph_color="${4:-}"

if [ -z "$session" ] || [ -z "$window" ]; then
  echo "usage: $0 <session> <window_name> <glyph> <glyph_color>" >&2
  exit 1
fi

tmp=$(mktemp "${meta}.XXXXXX")
jq \
  --arg s "$session" \
  --arg w "$window" \
  --arg g "$glyph" \
  --arg gc "$glyph_color" \
  '.[$s] = ((.[$s] // {}) | .[$w] = {glyph: $g, glyph_color: $gc})' \
  "$meta" > "$tmp"

mv "$tmp" "$meta"
