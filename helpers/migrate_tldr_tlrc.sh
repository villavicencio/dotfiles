#!/usr/bin/env bash
#
# migrate_tldr_tlrc.sh — remove the disabled tldr formula so tlrc, which the Brewfile
# now names, can own the `tldr` command.
#
# Homebrew disabled the tldr formula as unmaintained (2026-10) and names tlrc as its
# replacement. Both install bin/tldr, so on a Mac that still has the old formula linked,
# `brew bundle` installs tlrc but can't link it. The old formula can't be reinstalled
# anyway, so there's nothing to roll back to: this uninstalls it, then links tlrc if
# it's already installed (an earlier bundle left it unlinked). A Mac without the old
# formula is left alone, so reruns are no-ops. A failing `brew list` is an error,
# never read as "not installed".
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
printf '%s\n' "$formulae" | grep -qx tldr || exit 0
have_tlrc=0
printf '%s\n' "$formulae" | grep -qx tlrc && have_tlrc=1

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would uninstall the disabled tldr formula$([ "$have_tlrc" = 1 ] && echo ', then link tlrc')"
  exit 0
fi

echo "migrate_tldr_tlrc: removing the disabled tldr formula (Homebrew replaced it with tlrc)"
brew uninstall --formula --ignore-dependencies tldr
if [ "$have_tlrc" = 1 ]; then
  brew link --overwrite tlrc
fi
