#!/usr/bin/env bash
#
# migrate_vercel_cask.sh — swap an installed vercel / vercel-cli formula for the
# vercel cask, which both Brewfiles now name.
#
# Homebrew moved the vercel-cli formula to homebrew/cask/vercel (2026-10). On a
# machine that still has the formula, its `vercel` link sits where the cask
# installs its binary, so `brew bundle` can't install the cask. This removes
# the formula and installs the cask in one step, before the bundle runs.
#
# A machine with the cask already, or with neither, is left alone, so reruns
# are no-ops. If the cask install fails after the formula is gone, it exits 1
# with the command that restores `vercel`.
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

brew list --cask vercel >/dev/null 2>&1 && exit 0
old="$(brew list --formula -1 2>/dev/null | grep -xE 'vercel|vercel-cli' || true)"
[ -n "$old" ] || exit 0
names="$(printf '%s' "$old" | tr '\n' ' ')"

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would uninstall formula $names and install cask vercel"
  exit 0
fi

echo "migrate_vercel_cask: replacing formula $names with cask vercel (Homebrew moved it)"
# shellcheck disable=SC2086 # one name per word
brew uninstall --formula --force --ignore-dependencies $old
if ! brew install --cask vercel; then
  echo "ERROR: the vercel formula is gone but the cask didn't install; retry with: brew install --cask vercel" >&2
  exit 1
fi
