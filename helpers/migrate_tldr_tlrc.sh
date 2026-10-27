#!/usr/bin/env bash
#
# migrate_tldr_tlrc.sh — swap the disabled tldr formula for tlrc, which the Brewfile now
# names, so tlrc owns the `tldr` command.
#
# Homebrew disabled the tldr formula as unmaintained (2026-10) and names tlrc as its
# replacement. Both install bin/tldr, so on a Mac that still has the old formula linked,
# `brew bundle` installs tlrc but can't link it. This unlinks tldr, links (or installs)
# tlrc, and only then uninstalls tldr. If tlrc can't be linked or installed, tldr is
# relinked, so the command keeps working. A Mac whose tldr is gone but whose tlrc is
# installed and unlinked (an earlier run stopped part way) just gets tlrc linked. A Mac
# with neither problem is left alone, so reruns are no-ops. A failing `brew list` is an
# error, never read as "not installed".
#
# Invoked from helpers/install_packages.sh on the desk profile, BEFORE the main
# `brew bundle` (the server Brewfile has neither). macOS-only; honors DOTFILES_DRY_RUN=1.
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "migrate_tldr_tlrc: macOS only — nothing to do."
  exit 0
fi

# shellcheck source=helpers/init_homebrew.sh
. ./helpers/init_homebrew.sh

formulae="$(brew list --formula -1)" || { echo "ERROR: migrate_tldr_tlrc: brew list --formula failed" >&2; exit 1; }
have_old=0; have_tlrc=0
printf '%s\n' "$formulae" | grep -qx tldr && have_old=1
printf '%s\n' "$formulae" | grep -qx tlrc && have_tlrc=1
# The keg that owns bin/tldr now, if any.
owner="$(readlink "$HOMEBREW_PREFIX/bin/tldr" 2>/dev/null | sed -nE 's#.*/Cellar/([^/]+)/.*#\1#p' || true)"

if [ "$have_old" = 0 ]; then
  [ "$have_tlrc" = 1 ] && [ "$owner" != tlrc ] || exit 0
  # Something else owns bin/tldr (tealdeer, a hand-made link): leave it, never overwrite.
  if [ -e "$HOMEBREW_PREFIX/bin/tldr" ] || [ -L "$HOMEBREW_PREFIX/bin/tldr" ]; then
    echo "migrate_tldr_tlrc: $HOMEBREW_PREFIX/bin/tldr isn't tlrc's; leaving it. To use tlrc, remove it and run: brew link tlrc" >&2
    exit 0
  fi
  if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then echo "[dry-run] would link tlrc (installed, not linked)"; exit 0; fi
  echo "migrate_tldr_tlrc: linking tlrc (installed, not linked)"
  brew link tlrc
  exit 0
fi

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would unlink tldr, $([ "$have_tlrc" = 1 ] && echo link || echo install) tlrc, then uninstall tldr"
  exit 0
fi

echo "migrate_tldr_tlrc: replacing the disabled tldr formula with tlrc"
brew unlink tldr >/dev/null
# No --overwrite: unlinking tldr freed its own paths, and anything else in the way stays.
if [ "$have_tlrc" = 1 ]; then put=(brew link tlrc); else put=(brew install tlrc); fi
if ! "${put[@]}"; then
  if brew link tldr >/dev/null; then
    echo "ERROR: \`${put[*]}\` failed; relinked tldr, so the tldr command still works" >&2
  else
    echo "ERROR: \`${put[*]}\` failed, and tldr couldn't be relinked; run: brew link tldr" >&2
  fi
  exit 1
fi
brew uninstall --formula --ignore-dependencies tldr
