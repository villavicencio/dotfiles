#!/usr/bin/env bash
#
# migrate_legacy_fonts.sh — clear legacy Nerd Font collisions and install the
# font casks as ONE transactional, partial-failure-safe operation (P1-2).
#
# The old helpers/install_fonts.sh copied Nerd Font files straight into
# ~/Library/Fonts. Some basenames match what the font-jetbrains-mono-nerd-font
# cask installs but the BYTES differ (older Nerd Fonts release), so `brew bundle`
# cannot adopt them and the cask install fails on already-provisioned Macs.
# (The font-fira-code-nerd-font cask uses different basenames and never collides,
# so helpers/legacy-font-hashes.txt — the collision set — is JetBrains-only.)
#
# Everything from the first filesystem mutation onward runs under an ERR/EXIT
# cleanup TRAP: on any failure — a mid-move `mv`, a failed or dirty cask install,
# anything — the trap uninstalls every cask this run *attempted* (including one
# that failed after partially registering) and restores every moved original,
# verifying each is back. The trap is disarmed only after a clean commit. So a
# partial failure never leaves fonts displaced or a cask half-wired, and reruns
# are safe (fully migrated = no-op; partially migrated = finish the rest).
#
# Invoked from helpers/install_packages.sh AFTER brew is bootstrapped and BEFORE
# the main `brew bundle`. macOS-only; honors DOTFILES_DRY_RUN=1.
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "migrate_legacy_fonts: macOS only — nothing to do."
  exit 0
fi

DRY="${DOTFILES_DRY_RUN:-0}"
if ! command -v brew >/dev/null 2>&1; then
  echo "migrate_legacy_fonts: brew not on PATH — skipping (brew bundle will install fonts)."
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/legacy-font-hashes.txt"
FONTDIR="$HOME/Library/Fonts"
BACKUP="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/legacy-font-conflicts"
JB_CASK="font-jetbrains-mono-nerd-font"   # the cask whose targets the manifest lists
FIRA_CASK="font-fira-code-nerd-font"
CASKS="$JB_CASK $FIRA_CASK"

if [ ! -f "$MANIFEST" ]; then
  echo "migrate_legacy_fonts: manifest not found ($MANIFEST) — skipping." >&2
  exit 0
fi

occupied() { [ -e "$1" ] || [ -L "$1" ]; }   # true even for a dangling symlink

# Snapshot the installed casks with a command whose SUCCESS we verify. `brew list
# --cask` (no name) lists every installed cask and returns 0 on success. If that
# discovery itself fails we ABORT before any mutation (fail-closed) — never treat
# an operational error as "cask absent", which could otherwise move an already-
# installed cask's fonts or uninstall a pre-existing cask on rollback.
if ! installed_snapshot="$(brew list --cask 2>/dev/null)"; then
  echo "ERROR: 'brew list --cask' failed — cannot determine font-cask state; aborting before any change." >&2
  exit 1
fi
cask_installed() { printf '%s\n' "$installed_snapshot" | grep -qxF "$1"; }

# Which casks still need installing? (Only casks proven ABSENT in the verified
# snapshot are ever moved-for or uninstalled — the transaction's ownership rule.)
to_install=()
for c in $CASKS; do
  cask_installed "$c" || to_install+=("$c")
done
if [ "${#to_install[@]}" -eq 0 ]; then
  echo "migrate_legacy_fonts: font casks already installed — nothing to migrate."
  exit 0
fi

# Collisions only matter for a cask we are about to install. The manifest is the
# JetBrains cask's target set, so only clear it when JetBrains needs installing —
# never move files an already-installed cask manages.
installing_jb=0
for c in ${to_install[@]+"${to_install[@]}"}; do
  [ "$c" = "$JB_CASK" ] && installing_jb=1
done

collisions=()
if [ "$installing_jb" = "1" ]; then
  while read -r sha bn; do
    case "$sha" in ''|\#*) continue ;; esac
    [ -n "$bn" ] || continue
    occupied "$FONTDIR/$bn" && collisions+=("$bn")
  done < "$MANIFEST"
fi

if [ "$DRY" = "1" ]; then
  echo "migrate_legacy_fonts: [dry-run] install ${to_install[*]}; back up ${#collisions[@]} collision(s) first."
  for bn in ${collisions[@]+"${collisions[@]}"}; do echo "[dry-run] would move -> $BACKUP/: $bn"; done
  exit 0
fi

# ---- Transaction state + cleanup trap (armed before the first mutation) ----
moved=()             # basenames successfully moved to backup
declare -a moved_dest=()
owned=()             # casks THIS run installed (or dirtied) — rollback removes ONLY these
committed=0

rollback() {
  local c i target
  # Uninstall only casks we have POSITIVE proof this run created (or dirtied) —
  # never one an actor installed in the refresh→install gap (brew reported it as
  # "already installed", so it is NOT in `owned`). Best effort; failures surfaced.
  for c in ${owned[@]+"${owned[@]}"}; do
    brew uninstall --cask "$c" >/dev/null 2>&1 \
      || echo "WARN: could not uninstall $c during rollback (may not have registered)." >&2
  done
  # Restore every moved original — but only onto a now-free target. If a target
  # is still occupied (e.g. an uninstall failed to remove a cask file), leave the
  # original safely in the backup and SAY SO rather than silently dropping it.
  for i in ${moved[@]+"${!moved[@]}"}; do
    target="$FONTDIR/${moved[$i]}"
    if occupied "$target"; then
      echo "WARN: $target still occupied after rollback — your file is preserved at ${moved_dest[$i]}" >&2
    elif ! mv "${moved_dest[$i]}" "$target" 2>/dev/null; then
      echo "WARN: could not restore ${moved[$i]} — it remains at ${moved_dest[$i]}" >&2
    fi
  done
}

cleanup() {
  local rc=$?
  [ "$committed" = "1" ] && return
  echo "migrate_legacy_fonts: aborting (rc=$rc) — rolling back transaction." >&2
  rollback
}
trap cleanup EXIT

# ---- Mutations begin here (trap now armed) ----
# Move collisions aside (reversible) so the JetBrains cask can install.
if [ "${#collisions[@]}" -gt 0 ]; then
  mkdir -p "$BACKUP"
  chmod 700 "$BACKUP" 2>/dev/null || true
  for bn in "${collisions[@]}"; do
    dest="$BACKUP/$bn"; n=1
    while occupied "$dest"; do dest="$BACKUP/$bn.$n"; n=$((n + 1)); done
    mv "$FONTDIR/$bn" "$dest"          # if this fails, the trap restores prior moves
    moved+=("$bn"); moved_dest+=("$dest")
    echo "moved aside (reversible): $bn -> $dest"
  done
  for bn in "${collisions[@]}"; do
    if occupied "$FONTDIR/$bn"; then
      echo "ERROR: $bn still occupies $FONTDIR after move — aborting." >&2
      exit 1                           # trap restores everything moved so far
    fi
  done
fi

# Install each needed cask individually with POSITIVE ownership tracking:
#   * a CHECKED refresh (fail-closed) skips a cask an actor already installed;
#   * we own a cask (add to `owned`, so rollback may uninstall it) ONLY when our
#     own `brew install` actually created it — if brew reports "already installed"
#     (an actor won the refresh→install gap), we do NOT own it and never remove it;
#   * a nonzero install is treated as owned (it may have dirtied state) and triggers
#     rollback.
for c in "${to_install[@]}"; do
  if ! installed_snapshot="$(brew list --cask 2>/dev/null)"; then
    echo "ERROR: cask discovery failed mid-transaction — aborting." >&2
    exit 1                             # trap rolls back only what we own
  fi
  if cask_installed "$c"; then
    echo "migrate_legacy_fonts: $c appeared since the initial snapshot — leaving it to its owner."
    continue
  fi
  echo "migrate_legacy_fonts: installing $c ..."
  if out="$(brew install --cask "$c" 2>&1)"; then rc=0; else rc=$?; fi
  printf '%s\n' "$out"
  if [ "$rc" -ne 0 ]; then
    owned+=("$c")                      # may have partially registered — clean it up
    exit "$rc"                         # trap rolls back
  fi
  if printf '%s' "$out" | grep -qiE 'already installed'; then
    echo "migrate_legacy_fonts: $c was already installed by another actor — leaving it to its owner."
  else
    owned+=("$c")                      # positive proof this run installed it
  fi
done

# ---- Commit: disarm the trap, then tidy backups ----
committed=1
trap - EXIT

# Drop stale (dotfiles-owned) backups; keep + report the user's customized ones.
kept_user=0
if [ "${#moved[@]}" -gt 0 ]; then
  for idx in "${!moved[@]}"; do
    bn="${moved[$idx]}"; dest="${moved_dest[$idx]}"
    legacy_sha="$(awk -v b="$bn" '$2==b{print $1}' "$MANIFEST" | head -1)"
    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
      actual_sha="$(shasum -a 256 "$dest" | awk '{print $1}')"
    else
      actual_sha=""
    fi
    if [ -n "$legacy_sha" ] && [ "$actual_sha" = "$legacy_sha" ]; then
      rm -f "$dest"   # byte-identical to the dotfiles' own shipped blob — stale
    else
      kept_user=$((kept_user + 1))
      echo "kept your customized font in backup: $dest"
    fi
  done
fi

if [ "${#owned[@]}" -gt 0 ]; then
  msg="migrate_legacy_fonts: done — installed ${owned[*]}; ${#moved[@]} collision(s) cleared."
else
  msg="migrate_legacy_fonts: done — casks already present; ${#moved[@]} collision(s) cleared."
fi
[ "$kept_user" -gt 0 ] && msg="$msg $kept_user customized font(s) preserved under $BACKUP"
echo "$msg"
