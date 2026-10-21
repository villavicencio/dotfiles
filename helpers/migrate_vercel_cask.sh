#!/usr/bin/env bash
#
# migrate_vercel_cask.sh — swap an installed vercel / vercel-cli formula for the
# vercel cask, which both Brewfiles now name.
#
# Homebrew moved the vercel-cli formula to homebrew/cask/vercel (2026-10). On a
# machine that still has the formula, its `vercel` link sits where the cask
# installs its binary, so `brew bundle` can't install the cask. This unlinks
# the formula, installs the cask, and only then uninstalls the formula. If the
# cask install fails, the formula is relinked, so `vercel` keeps working.
#
# A machine with the cask already, or with neither, is left alone, so reruns
# are no-ops. A failing `brew list` is an error, never read as "not installed".
#
# Invoked from helpers/install_packages.sh on both macOS profiles, BEFORE the
# main `brew bundle`. macOS-only; honors DOTFILES_DRY_RUN=1.
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "migrate_vercel_cask: macOS only — nothing to do."
  exit 0
fi

# shellcheck source=helpers/init_homebrew.sh
. ./helpers/init_homebrew.sh

casks="$(brew list --cask -1)" || { echo "ERROR: migrate_vercel_cask: brew list --cask failed" >&2; exit 1; }
printf '%s\n' "$casks" | grep -qx vercel && exit 0
formulae="$(brew list --formula -1)" || { echo "ERROR: migrate_vercel_cask: brew list --formula failed" >&2; exit 1; }
old="$(printf '%s\n' "$formulae" | grep -xE 'vercel|vercel-cli' || true)"  # no match is fine
[ -n "$old" ] || exit 0
names="$(printf '%s' "$old" | tr '\n' ' ')"

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would unlink formula $names, install cask vercel, then uninstall the formula"
  exit 0
fi

# The keg that owns bin/vercel now (vercel-cli is usually an alias of the vercel
# keg), so a failed cask install relinks exactly that one.
linked="$(readlink "$HOMEBREW_PREFIX/bin/vercel" 2>/dev/null | sed -nE 's#.*/Cellar/([^/]+)/.*#\1#p')"

echo "migrate_vercel_cask: replacing formula $names with cask vercel (Homebrew moved it)"
for f in $old; do brew unlink "$f" >/dev/null; done
if ! brew install --cask vercel; then
  if [ -n "$linked" ] && brew link --overwrite "$linked" >/dev/null; then
    echo "ERROR: the vercel cask didn't install; relinked formula $linked, so vercel still works" >&2
  else
    echo "ERROR: the vercel cask didn't install, and formula $names couldn't be relinked; run: brew link --overwrite vercel" >&2
  fi
  exit 1
fi
# shellcheck disable=SC2086 # one name per word
brew uninstall --formula --force --ignore-dependencies $old
