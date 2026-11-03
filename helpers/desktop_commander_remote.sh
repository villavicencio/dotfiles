#!/bin/bash
#
# desktop_commander_remote.sh — the LaunchAgent job that keeps Desktop Commander's remote
# device running, so claude.ai chats can reach this Mac (VIL-571). The installer,
# helpers/install_desktop_commander_remote.sh, copies this file to
# ~/Library/Application Support/desktop-commander-remote/ and installs the pinned package
# beside it; launchd runs the copy. docs/reference/tooling.md has the why.
#
# Exit status is the contract with launchd (KeepAlive SuccessfulExit=false):
#   non-zero  restart me after ThrottleInterval
#   0         stay stopped; a "stopped" file says why, and re-running the installer clears it
# It stops for good instead of looping when the saved sign-in no longer works (a restart
# loop would open a browser tab each time) or after MAX_FAST quick crashes in a row.
set -uo pipefail

STATE_DIR="$HOME/Library/Application Support/desktop-commander-remote"
ENTRY="$STATE_DIR/pkg/node_modules/@wonderwhy-er/desktop-commander/dist/index.js"
STOP_FILE="$STATE_DIR/stopped"
FAILS_FILE="$STATE_DIR/fast-failures"
DEVICE_JSON="$HOME/.desktop-commander-device/device.json"
FAST_SECS=60
MAX_FAST=5
# Printed by the package when its saved session is gone and it starts a browser sign-in
# (dist/remote-device/device.js, 0.3.1). Re-check this string when bumping the version.
SIGNIN_LINE="Authenticating with Remote MCP server"
# Another copy of the remote device: `npx … remote` by hand, or a stray one. Two copies
# share one rotating refresh token, and replaying a spent one can revoke the session.
OTHER_COPY='desktop-commander.* remote( |$)'
# While running, how often to look for a copy started by hand. Finding one, this job stops
# its own copy (which saves its sign-in on the way out) and waits until the other exits.
WATCH_SECS=15
STEP_ASIDE_FILE="$STATE_DIR/stepped-aside"
# The plist's StandardOutPath (set by the installer). The package logs every command it
# receives in full, so the job keeps the log bounded (VIL-579): past LOG_MAX_BYTES, or
# LOG_MAX_DAYS after the last rotation, it becomes .1 and the older copies shift up, the
# oldest past LOG_KEEP dropped. Checked at start-up and on every watch below.
LOG="$HOME/Library/Logs/desktop-commander-remote.log"
LOG_MAX_BYTES=$(( 1024 * 1024 ))
LOG_MAX_DAYS=7
LOG_KEEP=2
LOG_STAMP="$STATE_DIR/log-rotated-at"  # its mtime is the last rotation
LOG_BY_AGE=1  # 0 once the stamp can't be written: from then on only the size counts
LOG_ROTATE=1  # 0 when $LOG isn't this job's stdout at start-up (see below)

log() { printf '%s  %s\n' "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# Copy, then truncate in place: launchd holds the log open, so a rename would leave the job
# writing into the renamed file. launchd opens it O_APPEND, so after the truncation every
# writer goes on at the new end. The rotation at start-up runs before the package does;
# while it runs, the watcher rotates, and a line written between its copy and its
# truncation is lost (a window of milliseconds, once a week or per LOG_MAX_BYTES).
# Copies are made under umask 077 and set to 600: the commands can hold anything.
# Every copy numbered LOG_KEEP or higher is deleted first, so lowering LOG_KEEP takes effect
# at the next rotation. If a copy can't be deleted or moved, or the new copy can't be
# written (a full disk, most likely), the rotation stops there (steps already done stay
# done), keeps no copy of this log, and still clears it, so it stays bounded; the log line
# after it says what failed.
rotate_log() {
  local f n i=$LOG_KEEP why=""
  for f in "$LOG".[0-9]*; do
    n=${f##*.}
    case $n in *[!0-9]*) continue ;; esac
    [ -e "$f" ] && [ "$n" -ge "$LOG_KEEP" ] || continue
    /bin/rm -f "$f" 2>/dev/null || { why="could not delete $f"; break; }
  done
  while [ -z "$why" ] && [ "$i" -gt 1 ]; do
    if [ -e "$LOG.$(( i - 1 ))" ]; then
      /bin/mv -f "$LOG.$(( i - 1 ))" "$LOG.$i" 2>/dev/null ||
        why="could not move $LOG.$(( i - 1 )) to $LOG.$i"
    fi
    i=$(( i - 1 ))
  done
  if [ -z "$why" ] &&
    ! { ( umask 077 && /bin/cp "$LOG" "$LOG.1" ) && /bin/chmod 600 "$LOG.1"; } 2>/dev/null; then
    why="could not write $LOG.1"
    [ -e "$LOG.1" ] && ! /bin/rm -f "$LOG.1" 2>/dev/null &&
      why="$why, and could not delete the partial copy there"
  fi
  : 2>/dev/null >"$LOG" || { log "could not clear $LOG to rotate it${why:+ ($why)}"; return 1; }
  /usr/bin/touch "$LOG_STAMP" 2>/dev/null || stamp_failed
  if [ -z "$why" ]; then
    log "log rotated ($1); the previous one is $LOG.1, up to $LOG_KEEP kept"
  else
    log "log cleared ($1) without keeping a copy: $why"
  fi
}

stamp_failed() {
  LOG_BY_AGE=0
  log "could not update $LOG_STAMP; rotating the log by size only until the job restarts"
}

# The file on this job's stdout (launchd's open log) and the file at $LOG, as device:inode.
# Rotation copies and clears $LOG, so it runs only while both are the same file. Otherwise
# a symlink at $LOG, or a log renamed or replaced while the job runs, would get a file the
# job doesn't write to rotated, and the one it does write to would grow unbounded.
# lsof takes about 30 ms; stat without -L sees a symlink itself, not its target.
stdout_file_id() {
  /usr/sbin/lsof -a -p "$$" -d 1 -F Di 2>/dev/null |
    /usr/bin/awk '/^D0x/ { d = substr($0, 4) } /^i/ { i = substr($0, 2) }
      END { if (d != "" && i != "") print tolower(d) ":" i }'
}
log_path_id() { /usr/bin/stat -f '%Xd:%i' "$LOG" 2>/dev/null | /usr/bin/tr 'A-F' 'a-f'; }

# Rotates when the log is over LOG_MAX_BYTES, or LOG_MAX_DAYS after the last rotation. With
# no stamp yet (first run) the age clock starts now. Once the stamp can't be written, only
# the size counts (LOG_BY_AGE), so a stale stamp can't rotate the log every 15 s.
# Returns 2, touching nothing, when $LOG isn't the file on stdout (missing, a symlink,
# renamed or replaced), and 3 when lsof can't tell.
rotate_log_if_due() {
  local size stamp out
  out=$(stdout_file_id)
  [ -n "$out" ] || return 3
  [ "$out" = "$(log_path_id)" ] || return 2
  size=$(/usr/bin/stat -f %z "$LOG" 2>/dev/null) || return 2
  if [ "$size" -ge "$LOG_MAX_BYTES" ]; then
    rotate_log "over $LOG_MAX_BYTES bytes"
    return
  fi
  [ "$LOG_BY_AGE" = 1 ] || return 0
  if ! stamp=$(/usr/bin/stat -f %m "$LOG_STAMP" 2>/dev/null); then
    /usr/bin/touch "$LOG_STAMP" 2>/dev/null || stamp_failed
    return 0
  fi
  [ $(( $(/bin/date +%s) - stamp )) -ge $(( LOG_MAX_DAYS * 86400 )) ] || return 0
  if [ "$size" -gt 0 ]; then
    rotate_log "$LOG_MAX_DAYS days since the last rotation"
  else
    /usr/bin/touch "$LOG_STAMP" 2>/dev/null || stamp_failed  # nothing to keep; restart the clock
  fi
}

# launchd has just opened $LOG, so a mismatch here means it isn't a plain file (a symlink)
# or this run's stdout isn't the log (started by hand): rotation stays off for this run,
# said once, instead of restarting in a loop. A match also resets the log to mode 600, in
# case launchd created it.
rotate_log_if_due
case $? in
  2|3) LOG_ROTATE=0
       log "not rotating the log this run: cannot confirm $LOG is the file this job writes to (a symlink, lsof failing, or started by hand)" ;;
  *) /bin/chmod 600 "$LOG" 2>/dev/null ;;
esac

stop_for_good() {
  log "STOPPED: $*"
  if ! printf '%s\n' "$*" 2>/dev/null >"$STOP_FILE"; then
    log "Could not write $STOP_FILE: it stays down until logout, then tries again at the next login."
  fi
  log "Fix that, then re-run helpers/install_desktop_commander_remote.sh to start again."
  exit 0
}

# Counts a quick failure: a run that died within FAST_SECS, or a start-up check that
# failed (no Node, pgrep error). MAX_FAST in a row stops the job. If the count can't be
# saved it stops at once: an unsaved count would never reach MAX_FAST, and the job would
# restart every ThrottleInterval for good.
fast_failure() {
  local n
  n=$(( $(cat "$FAILS_FILE" 2>/dev/null || echo 0) + 1 ))
  echo "$n" 2>/dev/null >"$FAILS_FILE" || stop_for_good "cannot save the failure count in $FAILS_FILE; last: $*"
  [ "$n" -ge "$MAX_FAST" ] && stop_for_good "$n quick failures in a row; last: $*"
  log "quick failure $n/$MAX_FAST: $*"
  exit 1
}

if [ -e "$STOP_FILE" ]; then
  log "stopped earlier: $(cat "$STOP_FILE"). Re-run the installer to start again."
  exit 0
fi
[ -s "$DEVICE_JSON" ] || stop_for_good "no saved sign-in at $DEVICE_JSON (sign in once in a terminal)"
[ -f "$ENTRY" ] || stop_for_good "package missing at $ENTRY (re-run the installer)"

# The stepped-aside marker only keeps the "waiting" line to one per wait; nothing else
# reads it, so failing to write or clear it costs repeated or missing log lines, no more.
/usr/bin/pgrep -f -- "$OTHER_COPY" >/dev/null; prc=$?
case $prc in
  0)
    [ -e "$STEP_ASIDE_FILE" ] ||
      log "another Desktop Commander remote is running (started by hand?); waiting for it to exit"
    : 2>/dev/null >"$STEP_ASIDE_FILE"
    exit 1 ;;
  1) ;;
  *) fast_failure "pgrep failed (status $prc); cannot tell whether another copy is running" ;;
esac
if [ -e "$STEP_ASIDE_FILE" ]; then
  rm -f "$STEP_ASIDE_FILE" 2>/dev/null || log "could not clear $STEP_ASIDE_FILE (affects log lines only)"
  log "the other copy is gone; starting"
fi

# Node comes from nvm through zshenv, so a Node upgrade (NODE_VERSION) needs no reinstall.
node_bin="$(/bin/zsh -c 'print -r -- "$NVM_DIR/versions/node/v$NODE_VERSION/bin"' 2>/dev/null)"
[ -x "$node_bin/node" ] || fast_failure "no node at '$node_bin' (check NVM_DIR/NODE_VERSION in zsh/zshenv)"

# At login the network may not be up yet; waiting here keeps that out of the failure count.
if ! /sbin/route -n get default >/dev/null 2>&1; then
  log "no network yet; waiting"
  until /sbin/route -n get default >/dev/null 2>&1; do sleep 30; done
fi

export PATH="$node_bin:/usr/bin:/bin:/usr/sbin:/sbin"
export DESKTOP_COMMANDER_DISABLE_TELEMETRY=1

fifo="$STATE_DIR/output.fifo"
rm -f "$fifo"
mkfifo -m 600 "$fifo" || fast_failure "cannot create $fifo"

start=$(/bin/date +%s)
node "$ENTRY" remote >"$fifo" 2>&1 </dev/null &
child=$!

# Watches for another copy while ours runs, and keeps the log bounded (rotate_log_if_due;
# the only rotation while the package runs, so two never overlap). If $LOG stops being
# the file this job writes to (renamed or replaced), it stops our child and exits
# LOG_MOVED, and the job exits 1 so launchd restarts it and reopens $LOG; the renamed
# file gets no more writes. Any match that isn't
# our child counts as another copy. On one it stops our child and exits STEPPED_ASIDE,
# which is how the main loop learns of it. A failed pgrep (status 2+) is logged and the
# watch goes on: stopping a working copy on a probe error would cut the remote off for nothing.
STEPPED_ASIDE=10
LOG_MOVED=11
(
  lsof_warned=0
  while sleep "$WATCH_SECS"; do
    if [ "$LOG_ROTATE" = 1 ]; then
      rotate_log_if_due
      case $? in
        2)
          trap '' TERM
          log "$LOG is no longer the file this job writes to (renamed or replaced?); restarting so launchd reopens it"
          kill -TERM "$child" 2>/dev/null
          exit "$LOG_MOVED" ;;
        3)
          [ "$lsof_warned" = 1 ] ||
            log "lsof failed; skipping log rotation until it works again"
          lsof_warned=1 ;;
        *) lsof_warned=0 ;;
      esac
    fi
    pids="$(/usr/bin/pgrep -f -- "$OTHER_COPY")"; prc=$?
    if [ "$prc" -gt 1 ]; then
      log "pgrep failed (status $prc) while watching for another copy; still watching"
      continue
    fi
    others="$(printf '%s\n' "$pids" | grep -v -x -e "$child" -e '')"
    if [ -n "$others" ]; then
      # From here on, ignore the main loop's TERM: once our child is stopped, the main loop
      # kills this watcher, and that must not beat the exit status that reports the step-aside.
      trap '' TERM
      log "another Desktop Commander remote started (pid $(printf '%s' "$others" | tr '\n' ' ')); stopping ours until it exits"
      : 2>/dev/null >"$STEP_ASIDE_FILE"
      kill -TERM "$child" 2>/dev/null
      exit "$STEPPED_ASIDE"
    fi
  done
) &
watcher=$!

stopping=0
trap 'stopping=1; kill -TERM "$child" "$watcher" 2>/dev/null' TERM INT HUP

# Pass the output through to the log and watch for the browser sign-in.
signin=0
while IFS= read -r line; do
  printf '%s\n' "$line"
  case $line in
    *"$SIGNIN_LINE"*) signin=1; kill -TERM "$child" 2>/dev/null ;;
  esac
done <"$fifo"
wait "$child"; rc=$?
kill -TERM "$watcher" 2>/dev/null
wait "$watcher"; wrc=$?
rm -f "$fifo"

[ "$stopping" = 1 ] && { log "stopped by launchd"; exit 0; }
# Stepped aside: restart later; the start-up check waits while the other copy runs.
[ "$wrc" = "$STEPPED_ASIDE" ] && exit 1
# The log was renamed or replaced: a restart has launchd reopen it.
[ "$wrc" = "$LOG_MOVED" ] && exit 1
[ "$signin" = 1 ] && stop_for_good "the saved sign-in no longer works (sign in once in a terminal)"

if [ $(( $(/bin/date +%s) - start )) -lt "$FAST_SECS" ]; then
  fast_failure "exited with status $rc after under ${FAST_SECS} s"
fi
echo 0 2>/dev/null >"$FAILS_FILE" ||
  log "could not reset $FAILS_FILE; earlier quick failures still count toward the stop"
log "exited with status $rc; launchd restarts it"
exit 1
