#!/usr/bin/env bash
#
# retire_desk_nvim_link.sh — server profile only: move aside a ~/.config/nvim link
# into this repo that an earlier desk install left behind.
#
# The server profile doesn't link ~/.config/nvim and skips the plugin bootstrap
# (base.yaml, install_nvim.sh), because the first `nvim` without that bootstrap
# installs plugins at branch HEAD and rewrites the tracked nvim/lazy-lock.json.
# Skipping the link only stops a new one being made: on a host that once had a
# desk install, the old link stays and nvim still loads the repo config.
#
# Only a symlink that resolves to this repo's nvim/ is moved. It goes to
# ~/.config/nvim.pre-dotfiles (or .pre-dotfiles.N), so nothing is deleted. A real
# directory or a link elsewhere is someone's own config and is left alone.
set -euo pipefail

if [ "${DOTFILES_PROFILE:-desk}" != "server" ]; then
  echo "retire_desk_nvim_link.sh: not the server profile; leaving ~/.config/nvim alone"
  exit 0
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TARGET="$HOME/.config/nvim"

if [ ! -L "$TARGET" ] || [ ! "$TARGET" -ef "$REPO/nvim" ]; then
  echo "nvim config: no desk link into this repo to retire"
  exit 0
fi

BACKUP="$TARGET.pre-dotfiles"; n=1
while [ -e "$BACKUP" ] || [ -L "$BACKUP" ]; do BACKUP="$TARGET.pre-dotfiles.$n"; n=$((n + 1)); done

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would move the desk link $TARGET aside to $BACKUP"
  exit 0
fi

# -n refuses to replace a destination that appears between the check and the
# move; the -L test after it turns that silent no-op into a failure.
mv -n "$TARGET" "$BACKUP"
if [ -L "$TARGET" ]; then
  echo "nvim config: could not move $TARGET aside (backup name taken)" >&2
  exit 1
fi
echo "nvim config: moved the desk link $TARGET aside to $BACKUP"
