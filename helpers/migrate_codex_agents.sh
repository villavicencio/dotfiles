#!/usr/bin/env bash
#
# migrate_codex_agents.sh — move a pre-existing regular ~/.codex/AGENTS.md aside so
# darwin.yaml can link ~/.codex/AGENTS.md -> codex/AGENTS.md.
#
# Dotbot's `relink: true` only replaces an existing SYMLINK. A regular file at the
# target (what Codex's "import from Claude Code" writes, and what every Mac had before
# this repo tracked the file) makes the link step fail and leaves the old instructions
# active. `force: true` would delete that file instead; the repo rule is never to
# delete user data, so this helper renames it to a timestamped backup and the link
# step then succeeds. A symlink or a missing file is left alone.
set -euo pipefail

TARGET="$HOME/.codex/AGENTS.md"

if [ -L "$TARGET" ] || [ ! -e "$TARGET" ]; then
  echo "codex AGENTS.md: nothing to migrate"
  exit 0
fi

# Only a regular file is ours to move. Anything else (a directory, a fifo) is left in
# place and fails the install loudly rather than being swept aside.
if [ ! -f "$TARGET" ]; then
  echo "codex AGENTS.md: $TARGET exists but is not a regular file; move it yourself" >&2
  exit 1
fi

# Never overwrite an earlier backup: pick a name that doesn't exist yet.
BACKUP="$TARGET.pre-dotfiles-$(date +%Y%m%d%H%M%S)"
n=0
while [ -e "$BACKUP" ] || [ -L "$BACKUP" ]; do
  n=$((n + 1))
  BACKUP="$TARGET.pre-dotfiles-$(date +%Y%m%d%H%M%S)-$n"
done

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would move $TARGET to $BACKUP"
  exit 0
fi

# -n refuses to replace a destination that appears between the check and the move;
# the -e test after it turns that silent no-op into a failure.
mv -n "$TARGET" "$BACKUP"
if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
  echo "codex AGENTS.md: could not move $TARGET aside (backup name taken)" >&2
  exit 1
fi
echo "codex AGENTS.md: moved the existing file to $BACKUP"
