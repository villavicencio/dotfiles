#!/bin/sh
#
# hal_memory_pull.sh — mirror Claude Code project memory from hal into the scriptorium vault.
#
# Projects whose working copy lives on hal as `david` (skills, bryancola.com) write their
# Claude Code memory to ~/.claude/projects/<slug>/memory/ in david's home on hal. hal has no
# Obsidian, so this job copies each of those folders into ~/Obsidian/scriptorium/<section>/memory/
# on the personal Mac: the section that the project's old vault became when obsidian-scriptorium's
# bin/migrate moved it into the one vault (VIL-721). It's one-way: hal is where memory is
# written, the section's memory/ is a read-only mirror and backup. An edit made there is
# replaced on the next run, whether or not anything changed on hal (the replaced folder is
# kept, see below).
#
# It writes only <section>/memory. It never creates the scriptorium vault, a section or an
# .obsidian folder: a section that doesn't exist yet (bin/migrate hasn't run for it) is
# skipped, and bin/migrate refuses a section it didn't place, so the job must not make one.
# The old vault ~/Obsidian/<vault>/ is never read or written.
#
# Installed by helpers/install_hal_memory_pull.sh as a copy (not a link into the repo, so
# a branch switch can't break it) and run by the LaunchAgent com.dvillavicencio.hal-memory-pull.
# Personal Mac only: it needs the `hal` ssh alias.
#
# Not rsync: macOS's /usr/bin/rsync is openrsync, and in testing (2026-10-21) it exited 0
# without updating a changed file. Instead each folder is pulled with tar into a staging
# dir, compared, and swapped in with mv. Staging and backups live outside the vault, in
# ~/.local/state/hal-memory-pull/ (same volume, so each mv is a rename): the folder a run
# replaces moves to backups/<section>/<UTC stamp>.<suffix>/memory/ there, so nothing is ever
# deleted, and no hidden folder is left inside the vault (bin/migrate refused vaults that had
# the old in-vault .sync-backup/).
#
# A missing or empty folder on hal leaves the section alone, as does an unreachable hal.
# Tests: ci/hal-memory-pull-checks.sh.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

# <slug on hal (david)>  <section name under ~/Obsidian/scriptorium>
PROJECTS='
-Users-david-Projects-skills skills
-Users-david-Projects-bryancola-com bryancola
'

PROJECTS="${HAL_MEMORY_PULL_PROJECTS:-$PROJECTS}"   # overrides are for testing
HOST="${HAL_MEMORY_PULL_HOST:-hal}"
SSH="${HAL_MEMORY_PULL_SSH:-ssh}"
OBSIDIAN="${HAL_MEMORY_PULL_OBSIDIAN:-$HOME/Obsidian}"
STATE="${HAL_MEMORY_PULL_STATE:-$HOME/.local/state/hal-memory-pull}"
VAULT="$OBSIDIAN/scriptorium"

# --sections prints the section names, one per line, for the installer to report on.
if [ "${1:-}" = "--sections" ]; then
  echo "$PROJECTS" | awk 'NF == 2 { print $2 }'
  exit 0
fi

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "$(ts) $*"; }

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would pull Claude memory from $HOST into $VAULT/<section>/memory"
  exit 0
fi

# True when $1 and $2 (followed through symlinks) are on one volume, so mv between them is
# a rename. same_volume compares with the vault root.
same_dev() { [ "$(stat -L -f %d "$1")" = "$(stat -L -f %d "$2")" ]; }
same_volume() { same_dev "$1" "$VAULT"; }

rc=0
pull_one() {
  slug=$1 section=$2 backup=
  sdir="$VAULT/$section"
  dest="$sdir/memory"
  if [ -L "$sdir" ]; then
    log "$section: $sdir is a symlink; not following it"
    rc=1; return
  elif [ ! -d "$sdir" ]; then
    log "$section: no section at $sdir yet (bin/migrate creates it); skipped"
    return
  fi
  if [ -L "$dest" ]; then
    log "$section: $dest is a symlink; section left alone"
    rc=1; return
  fi
  # A section (or its memory/) can be a mount point on another volume than the vault root:
  # compare each with stage/ and backups/ before anything moves.
  for d in "$sdir" "$dest"; do
    [ -e "$d" ] || continue
    if ! same_dev "$d" "$STATE/stage" || ! same_dev "$d" "$STATE/backups"; then
      log "$section: $d is not on the same volume as $STATE; section left alone"
      rc=1; return
    fi
  done

  stage=$(mktemp -d "$STATE/stage/$section.XXXXXX") || { log "$section: mktemp failed"; rc=1; return; }
  # Download to a file first: in a plain `ssh | tar` pipe only tar's status counts, so a
  # connection dropped mid-stream could extract (and swap in) a partial copy.
  # Exit 3 from the remote side means the folder doesn't exist there.
  "$SSH" -o BatchMode=yes -o ConnectTimeout=10 "$HOST" \
    "cd .claude/projects/$slug/memory 2>/dev/null || exit 3; tar -cf - ." \
    >"$stage.tar" 2>"$stage.err"
  st=$?
  if [ "$st" = 3 ]; then
    log "$section: $HOST:$slug/memory is missing; section left alone"
    rm -rf "$stage" "$stage.tar" "$stage.err"; return
  elif [ "$st" != 0 ]; then
    log "$section: pull failed (ssh $st): $(tr '\n' ' ' < "$stage.err")"
    rm -rf "$stage" "$stage.tar" "$stage.err"; rc=1; return
  fi
  if ! tar -xf "$stage.tar" -C "$stage" 2>"$stage.err"; then
    log "$section: could not unpack: $(tr '\n' ' ' < "$stage.err")"
    rm -rf "$stage" "$stage.tar" "$stage.err"; rc=1; return
  fi
  rm -f "$stage.tar" "$stage.err"

  if [ -z "$(ls -A "$stage")" ]; then
    log "$section: $HOST:$slug/memory is empty or missing; section left alone"
    rm -rf "$stage"; return
  fi

  if [ -d "$dest" ] && diff -rq "$dest" "$stage" >/dev/null 2>&1; then
    rm -rf "$stage" || { log "$section: unchanged, but could not remove $stage"; rc=1; }
    return
  fi

  if [ -d "$dest" ]; then
    # mktemp gives each backup its own folder, so two runs in the same second can't
    # collide (mv onto an existing folder would nest the old copy inside it).
    mkdir -p "$STATE/backups/$section" &&
      backup=$(mktemp -d "$STATE/backups/$section/$(date -u '+%Y%m%dT%H%M%SZ').XXXX") ||
      { log "$section: could not create a backup folder; section left alone"; rm -rf "$stage"; rc=1; return; }
    if ! same_dev "$backup" "$dest"; then
      log "$section: $backup is not on the same volume as $dest; section left alone"
      rm -rf "$stage"; rmdir "$backup" 2>/dev/null; rc=1; return
    fi
    if ! mv "$dest" "$backup/memory"; then
      log "$section: could not move the old memory aside; section left alone"
      rm -rf "$stage"; rmdir "$backup" 2>/dev/null; rc=1; return
    fi
  fi
  # If something recreated memory/ meanwhile, mv would put the stage inside it. Don't.
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    log "$section: $dest reappeared during the swap; staged copy left at $stage"
    rc=1; return
  fi
  if mv "$stage" "$dest"; then
    log "$section: updated from $HOST${backup:+ (previous copy in $backup/memory)}"
  else
    log "$section: swap failed; staged copy left at $stage"
    rc=1
  fi
}

# One run at a time. launchd never overlaps its own job, but a manual run can overlap it,
# and two runs swapping the same folder could leave a download in the wrong place. The
# script re-runs itself under lockf(1), which holds a kernel flock on the lock file for
# as long as the run lives: taking it is atomic, and the kernel drops it when the process
# exits or is killed, so there is no stale lock or recycled pid to reason about. -t 0
# fails at once (exit 75, EX_TEMPFAIL) while another run holds it; -k keeps the file.
# The lock is in the state dir, so the job writes nothing in ~/Obsidian but <section>/memory.
if [ -z "${HAL_MEMORY_PULL_LOCKED:-}" ]; then
  mkdir -p "$STATE/stage" || exit 1
  HAL_MEMORY_PULL_LOCKED=1 /usr/bin/lockf -k -s -t 0 "$STATE/run.flock" \
    /bin/sh "$0" "$@"
  st=$?
  if [ "$st" = 75 ]; then
    log "another run holds $STATE/run.flock; skipping"
    exit 0
  fi
  exit "$st"
fi

# The scriptorium vault must already exist; this job never creates it.
if [ -L "$VAULT" ] || [ ! -d "$VAULT/.obsidian" ]; then
  log "no scriptorium vault at $VAULT (a real folder with .obsidian/); nothing pulled"
  exit 1
fi
# Staging and backups are renamed into and out of the vault, so they must be on its volume:
# across volumes mv copies, and a half-copied memory/ could show up in the vault. Each
# backup folder is checked again where it is made (a link further down could point away).
mkdir -p "$STATE/backups" || exit 1
for d in "$STATE/stage" "$STATE/backups"; do
  if ! same_volume "$d"; then
    log "$d is not on the same volume as $VAULT; nothing pulled"
    exit 1
  fi
done

# Word-split the table in this shell (no pipe), so rc and log output survive the loop.
set -f
# shellcheck disable=SC2086
set -- $PROJECTS
set +f
while [ "$#" -ge 2 ]; do
  pull_one "$1" "$2"
  shift 2
done
exit "$rc"
