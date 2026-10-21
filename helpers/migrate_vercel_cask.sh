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
# A machine with neither is left alone, and one with both (an earlier cleanup
# failed) only loses the formula, so reruns finish the job. A failing `brew list` is an error, never read as "not installed".
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
formulae="$(brew list --formula -1)" || { echo "ERROR: migrate_vercel_cask: brew list --formula failed" >&2; exit 1; }
old="$(printf '%s\n' "$formulae" | grep -xE 'vercel|vercel-cli' || true)"  # no match is fine
[ -n "$old" ] || exit 0
names="$(printf '%s' "$old" | tr '\n' ' ')"

# The cask is in but the formula is still here: an earlier run's cleanup failed.
# Uninstalling the keg leaves the cask's bin links alone (they point into the
# Caskroom), so finish it.
have_cask=0
printf '%s\n' "$casks" | grep -qx vercel && have_cask=1

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  if [ "$have_cask" = 1 ]; then echo "[dry-run] would uninstall leftover formula $names (cask vercel is installed)"
  else echo "[dry-run] would unlink formula $names, install cask vercel, then uninstall the formula"; fi
  exit 0
fi

if [ "$have_cask" = 1 ]; then
  echo "migrate_vercel_cask: cask vercel is installed; removing leftover formula $names"
  # shellcheck disable=SC2086 # one name per word
  brew uninstall --formula --force --ignore-dependencies $old
  exit 0
fi

# The keg that owns bin/vercel now (vercel-cli is usually an alias of the vercel
# keg), so a failure relinks exactly that one.
linked="$(readlink "$HOMEBREW_PREFIX/bin/vercel" 2>/dev/null | sed -nE 's#.*/Cellar/([^/]+)/.*#\1#p' || true)"  # unlinked: empty
relink() {
  local keg=${linked:-$(printf '%s\n' "$old" | head -1)}
  if brew link --overwrite "$keg" >/dev/null; then
    echo "ERROR: $1; relinked formula $keg, so vercel still works" >&2
  else
    echo "ERROR: $1, and formula $keg couldn't be relinked; run: brew link --overwrite $keg" >&2
  fi
  exit 1
}

echo "migrate_vercel_cask: replacing formula $names with cask vercel (Homebrew moved it)"
for f in $old; do brew unlink "$f" >/dev/null || relink "couldn't unlink formula $f"; done
if ! brew install --cask vercel; then
  # A cask that failed after registering may own bin/vercel now. Remove it
  # before relinking, so the formula never overwrites the cask's link. If it
  # won't go, or Homebrew can't say whether it's there, stop without relinking.
  fix="brew uninstall --cask --force vercel; brew link --overwrite ${linked:-vercel}"
  casks="$(brew list --cask -1)" || {
    echo "ERROR: the vercel cask didn't install, and brew list --cask failed, so it's unknown whether a half-installed cask owns bin/vercel; check, then run: $fix" >&2
    exit 1
  }
  if printf '%s\n' "$casks" | grep -qx vercel && ! brew uninstall --cask --force vercel; then
    echo "ERROR: the vercel cask half-installed and couldn't be removed; run: $fix" >&2
    exit 1
  fi
  relink "the vercel cask didn't install"
fi
# shellcheck disable=SC2086 # one name per word
brew uninstall --formula --force --ignore-dependencies $old
