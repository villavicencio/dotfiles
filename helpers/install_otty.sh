#!/usr/bin/env bash
#
# install_otty.sh — seed the Otty terminal config on a fresh macOS machine.
#
# SEED-ONLY BY DESIGN. Otty is the one tracked config that must NOT be
# symlinked: `otty config set` and the Settings UI both write via temp-file +
# atomic rename, which replaces the path outright. A symlink at
# ~/.config/otty/config.toml therefore survives exactly until the first setting
# change, after which the live config is a regular file and the repo copy is a
# silently-orphaned stale twin. Verified against otty 1.3.1 — see
# docs/solutions/integration-issues/otty-config-symlink-hostile-atomic-rename-2026-08-07.md
#
# So: copy in only what is absent, never clobber a live config, and let
# `dot drift` surface the gap when the two diverge.
#
# Usage:
#   install_otty.sh              seed ~/.config/otty from the repo (skips what exists)
#   install_otty.sh --capture    the reverse — record live changes back into the repo
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_CONFIG="$REPO_ROOT/otty/config.toml"
SRC_THEME="$REPO_ROOT/otty/themes/com-googlecode-iterm2.ottytheme"
DEST_DIR="$HOME/.config/otty"

# --- capture: live -> repo -------------------------------------------------
# The tracked config is the NORMALIZED (`otty config show`) form, not a raw copy
# of the live file — the live one carries a growing tail of
# `# key = value (reset to default)` comments. So capture regenerates rather
# than `cp`s, and re-prepends the tracked file's leading comment header (every
# line up to the first blank) so the explanation survives the round trip.
if [ "${1:-}" = "--capture" ]; then
  command -v otty >/dev/null 2>&1 || { echo "Error: otty not on PATH" >&2; exit 1; }
  [ -f "$DEST_DIR/config.toml" ] || { echo "Error: no live config at $DEST_DIR/config.toml" >&2; exit 1; }
  [ -f "$SRC_CONFIG" ] || { echo "Error: tracked config missing at $SRC_CONFIG" >&2; exit 1; }

  # Header = everything up to the first blank line. Command substitution strips
  # the trailing newline(s), so the separating blank is re-emitted explicitly
  # below — without it the next --capture would run past the header and swallow
  # config lines into it.
  header="$(sed -n '1,/^$/p' "$SRC_CONFIG")"
  case "$header" in
    '#'*) : ;;
    *) echo "Error: $SRC_CONFIG does not start with a comment header — refusing to rewrite" >&2; exit 1 ;;
  esac
  if ! body="$(otty config show --config-file "$DEST_DIR/config.toml" 2>/dev/null)"; then
    echo "Error: 'otty config show' failed on the live config — nothing captured" >&2; exit 1
  fi
  # Write via a temp file so an interrupted run can't leave a truncated tracked config.
  tmp="$SRC_CONFIG.tmp.$$"
  if ! printf '%s\n\n%s\n' "$header" "$body" > "$tmp"; then
    rm -f "$tmp"; echo "Error: failed writing $tmp" >&2; exit 1
  fi
  if ! mv "$tmp" "$SRC_CONFIG"; then
    rm -f "$tmp"; echo "Error: failed replacing $SRC_CONFIG" >&2; exit 1
  fi

  if [ -f "$DEST_DIR/themes/com-googlecode-iterm2.ottytheme" ]; then
    cp "$DEST_DIR/themes/com-googlecode-iterm2.ottytheme" "$SRC_THEME"
  fi
  echo "Captured live Otty config into $SRC_CONFIG — review with: git diff otty/"
  exit 0
fi

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would seed ~/.config/otty/{config.toml,themes/com-googlecode-iterm2.ottytheme} if absent"
  exit 0
fi

# Otty is a macOS app; nothing to seed elsewhere.
if [ "$(uname)" != "Darwin" ]; then
  echo "Skipping Otty config (not macOS)."
  exit 0
fi

mkdir -p "$DEST_DIR/themes" || { echo "Error: cannot create $DEST_DIR/themes" >&2; exit 1; }

# seed <src> <dest> <label>
seed() {
  local src="$1" dest="$2" label="$3"
  if [ ! -f "$src" ]; then
    echo "Error: tracked $label missing at $src" >&2
    return 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "Otty $label already present, leaving it alone (run 'dot drift' to compare)."
    return 0
  fi
  cp "$src" "$dest" && echo "Seeded Otty $label -> $dest"
}

rc=0
seed "$SRC_CONFIG" "$DEST_DIR/config.toml" "config" || rc=1
# The iTerm2-imported theme is user-authored and ships with nothing; Otty
# re-seeds its own 24 reference themes (nord, dracula, …) on first run, so
# those are deliberately not tracked.
seed "$SRC_THEME" "$DEST_DIR/themes/com-googlecode-iterm2.ottytheme" "iTerm2-imported theme" || rc=1

exit "$rc"
