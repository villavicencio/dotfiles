#!/bin/sh
#
# hal_memory_pull.sh — mirror Claude Code project memory from hal into Obsidian vaults.
#
# Projects whose working copy lives on hal as `david` (skills, bryancola.com) write their
# Claude Code memory to /Users/david/.claude/projects/<slug>/memory/ on hal. hal has no
# Obsidian, so this job copies each of those folders into ~/Obsidian/<vault>/memory/ on
# the personal Mac. It's one-way: hal is where memory is written, the vault is a read-only
# mirror and backup. An edit made in the vault is replaced on the next run, whether or
# not anything changed on hal (the replaced folder is kept, see below).
#
# Installed by helpers/install_hal_memory_pull.sh as a copy (not a link into the repo, so
# a branch switch can't break it) and run by the LaunchAgent com.dvillavicencio.hal-memory-pull.
# Personal Mac only: it needs the `hal` ssh alias.
#
# Not rsync: macOS's /usr/bin/rsync is openrsync, and in testing (2026-10-21) it exited 0
# without updating a changed file. Instead each folder is pulled with tar into a staging
# dir inside the vault, compared, and swapped in with mv. The folder it replaces moves to
# ~/Obsidian/<vault>/.sync-backup/<UTC stamp>.<suffix>/memory/, so nothing is ever deleted. Obsidian
# ignores dot-folders, so backups don't show up as notes.
#
# A missing or empty folder on hal leaves the vault alone, as does an unreachable hal.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

# <slug on hal (david)>  <vault name under ~/Obsidian>
PROJECTS='
-Users-david-Projects-skills skills
-Users-david-Projects-bryancola-com bryancola
'

PROJECTS="${HAL_MEMORY_PULL_PROJECTS:-$PROJECTS}"   # overrides are for testing
HOST="${HAL_MEMORY_PULL_HOST:-hal}"
OBSIDIAN="${HAL_MEMORY_PULL_OBSIDIAN:-$HOME/Obsidian}"

# --vaults prints the vault names, one per line, for the installer to bootstrap.
if [ "${1:-}" = "--vaults" ]; then
  echo "$PROJECTS" | awk 'NF == 2 { print $2 }'
  exit 0
fi

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "$(ts) $*"; }

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would pull Claude memory from $HOST into $OBSIDIAN/<vault>/memory"
  exit 0
fi

rc=0
pull_one() {
  slug=$1 vault=$2 backup=
  vdir="$OBSIDIAN/$vault"
  dest="$vdir/memory"
  if [ ! -d "$vdir" ]; then
    log "$vault: no vault at $vdir; run helpers/install_hal_memory_pull.sh"
    rc=1; return
  fi

  stage=$(mktemp -d "$vdir/.sync-stage.XXXXXX") || { log "$vault: mktemp failed"; rc=1; return; }
  # Download to a file first: in a plain `ssh | tar` pipe only tar's status counts, so a
  # connection dropped mid-stream could extract (and swap in) a partial copy.
  # Exit 3 from the remote side means the folder doesn't exist there.
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" \
    "cd .claude/projects/$slug/memory 2>/dev/null || exit 3; tar -cf - ." \
    >"$stage.tar" 2>"$stage.err"
  st=$?
  if [ "$st" = 3 ]; then
    log "$vault: $HOST:$slug/memory is missing; vault left alone"
    rm -rf "$stage" "$stage.tar" "$stage.err"; return
  elif [ "$st" != 0 ]; then
    log "$vault: pull failed (ssh $st): $(tr '\n' ' ' < "$stage.err")"
    rm -rf "$stage" "$stage.tar" "$stage.err"; rc=1; return
  fi
  if ! tar -xf "$stage.tar" -C "$stage" 2>"$stage.err"; then
    log "$vault: could not unpack: $(tr '\n' ' ' < "$stage.err")"
    rm -rf "$stage" "$stage.tar" "$stage.err"; rc=1; return
  fi
  rm -f "$stage.tar" "$stage.err"

  if [ -z "$(ls -A "$stage")" ]; then
    log "$vault: $HOST:$slug/memory is empty or missing; vault left alone"
    rm -rf "$stage"; return
  fi

  if [ -d "$dest" ] && diff -rq "$dest" "$stage" >/dev/null 2>&1; then
    rm -rf "$stage" || { log "$vault: unchanged, but could not remove $stage"; rc=1; }
    return
  fi

  if [ -d "$dest" ]; then
    # mktemp gives each backup its own folder, so two runs in the same second can't
    # collide (mv onto an existing folder would nest the old copy inside it).
    mkdir -p "$vdir/.sync-backup" &&
      backup=$(mktemp -d "$vdir/.sync-backup/$(date -u '+%Y%m%dT%H%M%SZ').XXXX") ||
      { log "$vault: could not create a backup folder; vault left alone"; rm -rf "$stage"; rc=1; return; }
    if ! mv "$dest" "$backup/memory"; then
      log "$vault: could not move the old memory aside; vault left alone"
      rm -rf "$stage"; rmdir "$backup" 2>/dev/null; rc=1; return
    fi
  fi
  # If something recreated memory/ meanwhile, mv would put the stage inside it. Don't.
  if [ -e "$dest" ]; then
    log "$vault: $dest reappeared during the swap; staged copy left at $stage"
    rc=1; return
  fi
  if mv "$stage" "$dest"; then
    log "$vault: updated from $HOST${backup:+ (previous copy in ${backup#"$vdir"/}/memory)}"
  else
    log "$vault: swap failed; staged copy left at $stage"
    rc=1
  fi
}

# One run at a time. launchd never overlaps its own job, but a manual run can overlap it,
# and two runs swapping the same folder could leave a download in the wrong place. The
# script re-runs itself under lockf(1), which holds a kernel flock on the lock file for
# as long as the run lives: taking it is atomic, and the kernel drops it when the process
# exits or is killed, so there is no stale lock or recycled pid to reason about. -t 0
# fails at once (exit 75, EX_TEMPFAIL) while another run holds it; -k keeps the file.
if [ -z "${HAL_MEMORY_PULL_LOCKED:-}" ]; then
  mkdir -p "$OBSIDIAN" || exit 1
  HAL_MEMORY_PULL_LOCKED=1 /usr/bin/lockf -k -s -t 0 "$OBSIDIAN/.hal-memory-pull.lock" \
    /bin/sh "$0" "$@"
  st=$?
  if [ "$st" = 75 ]; then
    log "another run holds $OBSIDIAN/.hal-memory-pull.lock; skipping"
    exit 0
  fi
  exit "$st"
fi

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
