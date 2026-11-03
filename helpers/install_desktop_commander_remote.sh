#!/usr/bin/env bash
#
# install_desktop_commander_remote.sh — install (or --remove) the LaunchAgent that keeps
# Desktop Commander's remote device running, so claude.ai chats can reach this Mac
# (VIL-571). helpers/desktop_commander_remote.sh explains the job itself;
# docs/reference/tooling.md ("Desktop Commander remote") has the why and the decisions.
#
# Personal Mac only, run by hand; ./install doesn't call it. It needs a saved sign-in
# (~/.desktop-commander-device/device.json): run the remote device once in a terminal and
# finish the browser sign-in first. Re-run it after a stop (the log says why), after
# changing the job script, or after bumping DC_VERSION; the job runs from a copy, so a
# branch switch in this repo can't leave the LaunchAgent pointing at a missing file.
#
# What it does, each step idempotent:
#   1. Stages the pinned package (npm, telemetry off), the job and the plist beside their
#      targets in ~/Library/Application Support/desktop-commander-remote/ and
#      ~/Library/LaunchAgents/. A failure here leaves a running agent untouched.
#   2. Stops the agent and refuses to go on while any copy of the remote device still runs
#      (two copies share one rotating refresh token, which can revoke it).
#   3. Moves the staged files into place and loads the agent (at login, restarted when it
#      fails, log in ~/Library/Logs/desktop-commander-remote.log). npm's cache in ~/.npm
#      keeps a copy of the package too.
#
# Undo: bash helpers/install_desktop_commander_remote.sh --remove. That keeps the saved
# sign-in; to end it, run the remote device with --logout and revoke the device in the
# Remote MCP dashboard.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.dvillavicencio.desktop-commander-remote"
# Pinned; bump by hand after reading the release (and re-check SIGNIN_LINE in the job).
DC_VERSION="0.3.1"
PKG_SPEC="@wonderwhy-er/desktop-commander@$DC_VERSION"
JOB_SRC="$REPO/helpers/desktop_commander_remote.sh"
JOB_DIR="$HOME/Library/Application Support/desktop-commander-remote"
JOB="$JOB_DIR/desktop-commander-remote.sh"
PKG="$JOB_DIR/pkg"
ENTRY="$PKG/node_modules/@wonderwhy-er/desktop-commander/dist/index.js"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/desktop-commander-remote.log"
DEVICE_JSON="$HOME/.desktop-commander-device/device.json"
OTHER_COPY='desktop-commander.* remote( |$)'

usage() { echo "usage: $0 [--remove]" >&2; exit 2; }
mode=install
case $# in
  0) ;;
  1) if [ "$1" = --remove ]; then mode=remove; else usage; fi ;;
  *) usage ;;
esac

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  if [ "$mode" = remove ]; then
    echo "[dry-run] would unload $LABEL and remove $PLIST and $JOB_DIR"
  else
    echo "[dry-run] would install $PKG_SPEC in $PKG and load $LABEL (plist at $PLIST)"
  fi
  exit 0
fi

if [ "$(uname)" != "Darwin" ]; then
  echo "install_desktop_commander_remote.sh: personal Mac only; skipping on $(uname)"
  exit 0
fi

domain="gui/$(id -u)"

# Unloads our agent and waits up to 10 s for every copy of the remote device to exit.
# Fails, saying why, if the agent is still loaded or any copy (ours or one started by
# hand) is still running.
stop_agent() {
  launchctl bootout "$domain/$LABEL" 2>/dev/null || true
  if launchctl print "$domain/$LABEL" >/dev/null 2>&1; then
    echo "Error: $LABEL is still loaded after launchctl bootout" >&2
    return 1
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    /usr/bin/pgrep -f -- "$OTHER_COPY" >/dev/null || return 0
    sleep 1
  done
  echo "Error: a Desktop Commander remote device is still running (started by hand?)." >&2
  echo "Stop it (Ctrl+C in its terminal), then re-run this installer. Running:" >&2
  /usr/bin/pgrep -fl -- "$OTHER_COPY" >&2
  return 1
}

if [ "$mode" = remove ]; then
  stop_agent || exit 1
  if ! { rm -f "$PLIST" && rm -rf "$JOB_DIR"; }; then
    echo "Error: cannot remove $PLIST or $JOB_DIR" >&2; exit 1
  fi
  echo "$LABEL removed. The saved sign-in stays in $DEVICE_JSON."
  exit 0
fi

# Checks and staging come first, so a failed reinstall leaves the running agent alone.
if [ ! -s "$DEVICE_JSON" ]; then
  echo "Error: no saved sign-in at $DEVICE_JSON. Run this in a terminal, finish the browser" >&2
  echo "sign-in, press Ctrl+C, then re-run this installer:" >&2
  echo "  npx --yes $PKG_SPEC remote" >&2
  exit 1
fi

node_bin="$(/bin/zsh -c 'print -r -- "$NVM_DIR/versions/node/v$NODE_VERSION/bin"' 2>/dev/null)"
if [ ! -x "$node_bin/npm" ]; then
  echo "Error: no npm at '$node_bin' (NVM_DIR/NODE_VERSION from zsh/zshenv)" >&2
  exit 1
fi

if ! { mkdir -p "$JOB_DIR" "$(dirname "$PLIST")" "$(dirname "$LOG")" && chmod 700 "$JOB_DIR"; }; then
  echo "Error: cannot create $JOB_DIR or its siblings" >&2; exit 1
fi

# Staged paths; whatever hasn't been moved into place is removed on exit.
new="" job_tmp="" plist_tmp=""
trap 'rm -rf "$new" "$job_tmp" "$plist_tmp"' EXIT

new="$(mktemp -d "$JOB_DIR/.pkg.XXXXXX")" || exit 1
echo "Installing $PKG_SPEC ..."
if ! PATH="$node_bin:$PATH" DESKTOP_COMMANDER_DISABLE_TELEMETRY=1 \
    "$node_bin/npm" install --prefix "$new" --save-exact --no-fund --no-audit --loglevel=error "$PKG_SPEC" ||
   [ ! -f "$new/${ENTRY#"$PKG"/}" ]; then
  echo "Error: npm install of $PKG_SPEC failed" >&2; exit 1
fi

job_tmp="$(mktemp "$JOB_DIR/.job.XXXXXX")" || exit 1
if ! { cp "$JOB_SRC" "$job_tmp" && chmod 755 "$job_tmp"; }; then
  echo "Error: cannot stage $JOB_SRC" >&2; exit 1
fi

plist_tmp="$(mktemp "$(dirname "$PLIST")/.$LABEL.XXXXXX")" || exit 1
# printf, not a heredoc: see "No heredocs in bin/dot" in docs/reference/tooling.md.
# KeepAlive SuccessfulExit=false: the job exits 0 only when it means to stay stopped.
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0">' \
  '<dict>' \
  "  <key>Label</key><string>$LABEL</string>" \
  '  <key>ProgramArguments</key>' \
  "  <array><string>/bin/bash</string><string>$JOB</string></array>" \
  '  <key>RunAtLoad</key><true/>' \
  '  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>' \
  '  <key>ThrottleInterval</key><integer>30</integer>' \
  "  <key>StandardOutPath</key><string>$LOG</string>" \
  "  <key>StandardErrorPath</key><string>$LOG</string>" \
  '</dict>' \
  '</plist>' >"$plist_tmp"
if ! plutil -lint -s "$plist_tmp"; then
  echo "Error: generated plist failed plutil -lint" >&2; exit 1
fi

# Everything is staged: stop the agent, then move it all into place.
stop_agent || exit 1

old="$PKG.old"
if ! rm -rf "$old"; then echo "Error: cannot clear $old" >&2; exit 1; fi
if [ -e "$PKG" ] && ! mv "$PKG" "$old"; then
  echo "Error: cannot move the old package aside" >&2; exit 1
fi
if ! mv "$new" "$PKG"; then
  [ -e "$old" ] && mv "$old" "$PKG"
  echo "Error: cannot move the new package into $PKG (old one restored)" >&2; exit 1
fi
rm -rf "$old"

if ! { mv -f "$job_tmp" "$JOB" && mv -f "$plist_tmp" "$PLIST"; }; then
  echo "Error: cannot move the job or the plist into place" >&2; exit 1
fi

# A fresh start: clear an earlier stop and the quick-failure count; log readable by you only.
if ! rm -f "$JOB_DIR/stopped" "$JOB_DIR/fast-failures"; then
  echo "Error: cannot clear the earlier stop in $JOB_DIR" >&2; exit 1
fi
if ! { touch "$LOG" && chmod 600 "$LOG"; }; then
  echo "Error: cannot prepare $LOG" >&2; exit 1
fi

if ! launchctl bootstrap "$domain" "$PLIST"; then
  echo "Error: launchctl bootstrap failed for $PLIST" >&2
  exit 1
fi
echo "$LABEL loaded ($PKG_SPEC). Log: $LOG"
