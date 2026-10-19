#!/bin/sh
# Set up the hal pilot runner (VIL-396). Run as david on hal, from the
# dotfiles clone: ~/Projects/Personal/dotfiles/pilot/install.sh
# It makes ~/runs, checks the two secrets, and renders the LaunchDaemon plist
# into ~/runs/. Loading the daemon needs admin; the commands are printed at
# the end. Nothing here touches ~/.ssh, gh's login or LM Studio.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
RUNS="$HOME/runs"
SECRETS="$HOME/.config/hal-pilot"

[ "$(uname)" = Darwin ] || { echo "install.sh: macOS only" >&2; exit 1; }
[ "$HERE" = "$HOME/Projects/Personal/dotfiles/pilot" ] || {
  echo "install.sh: the plist runs $HOME/Projects/Personal/dotfiles/pilot/runner.py;" >&2
  echo "  run install.sh from that clone, not $HERE" >&2; exit 1; }

for s in gh-token lmstudio-token; do
  f="$SECRETS/$s"
  [ -s "$f" ] || { echo "install.sh: missing $f" >&2; exit 1; }
  mode=$(/usr/bin/stat -f %Lp "$f")
  [ "$mode" = 600 ] || { echo "install.sh: $f is mode $mode, want 600" >&2; exit 1; }
done

mkdir -p "$RUNS/queue" "$RUNS/log" "$RUNS/work" "$RUNS/repos"
chmod 700 "$RUNS"

out="$RUNS/dev.hal.pilot.plist"
sed -e "s#@HOME@#$HOME#g" -e "s#@USER@#$(id -un)#g" "$HERE/dev.hal.pilot.plist.in" > "$out"
plutil -lint "$out" >/dev/null
echo "rendered $out"
cat <<MSG

Next, as admin on hal (admin's password). Safe to repeat after a change:
  sudo cp $out /Library/LaunchDaemons/dev.hal.pilot.plist
  sudo chown root:wheel /Library/LaunchDaemons/dev.hal.pilot.plist
  sudo launchctl bootout system/dev.hal.pilot 2>/dev/null   # only if already loaded
  sudo launchctl bootstrap system /Library/LaunchDaemons/dev.hal.pilot.plist

Run once now, outside the schedule:
  sudo launchctl kickstart system/dev.hal.pilot
Remove it:
  sudo launchctl bootout system/dev.hal.pilot
MSG
