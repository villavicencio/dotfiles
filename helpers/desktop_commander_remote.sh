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

log() { printf '%s  %s\n' "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

stop_for_good() {
  log "STOPPED: $*"
  if ! printf '%s\n' "$*" 2>/dev/null >"$STOP_FILE"; then
    log "Could not write $STOP_FILE: it stays down until logout, then tries again at the next login."
  fi
  log "Fix that, then re-run helpers/install_desktop_commander_remote.sh to start again."
  exit 0
}

# Counts a run that died within FAST_SECS; MAX_FAST in a row stops the job.
fast_failure() {
  local n
  n=$(( $(cat "$FAILS_FILE" 2>/dev/null || echo 0) + 1 ))
  echo "$n" >"$FAILS_FILE"
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

if /usr/bin/pgrep -f -- "$OTHER_COPY" >/dev/null; then
  # Logged once per wait, not on every 30 s retry.
  [ -e "$STEP_ASIDE_FILE" ] ||
    log "another Desktop Commander remote is running (started by hand?); waiting for it to exit"
  : >"$STEP_ASIDE_FILE" 2>/dev/null
  exit 1
fi
[ -e "$STEP_ASIDE_FILE" ] && { rm -f "$STEP_ASIDE_FILE"; log "the other copy is gone; starting"; }

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

# Watches for another copy while ours runs. Every match that isn't our child counts; a
# failed pgrep (status 2+) is skipped, not taken as a match.
(
  while sleep "$WATCH_SECS"; do
    others="$(/usr/bin/pgrep -f -- "$OTHER_COPY" | grep -v -x "$child")"
    if [ -n "$others" ]; then
      log "another Desktop Commander remote started (pid $(echo "$others" | tr '\n' ' ')); stopping ours until it exits"
      : >"$STEP_ASIDE_FILE" 2>/dev/null
      kill -TERM "$child" 2>/dev/null
      exit 0
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
rm -f "$fifo"

[ "$stopping" = 1 ] && { log "stopped by launchd"; exit 0; }
# Stepped aside: restart later; the start-up check waits while the other copy runs.
[ -e "$STEP_ASIDE_FILE" ] && exit 1
[ "$signin" = 1 ] && stop_for_good "the saved sign-in no longer works (sign in once in a terminal)"

if [ $(( $(/bin/date +%s) - start )) -lt "$FAST_SECS" ]; then
  fast_failure "exited with status $rc after under ${FAST_SECS} s"
fi
echo 0 >"$FAILS_FILE"
log "exited with status $rc; launchd restarts it"
exit 1
