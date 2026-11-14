#!/usr/bin/env bash
#
# install_hal_memory_pull.sh — install the LaunchAgent that mirrors Claude Code memory
# from hal into sections of the scriptorium vault (helpers/hal_memory_pull.sh explains the
# job itself).
#
# Personal Mac only, run by hand; ./install doesn't call it, because the work Mac has no
# `hal` alias. Re-run it after changing hal_memory_pull.sh: the job runs from a copy, so
# a branch switch in this repo can't leave the LaunchAgent pointing at a missing file
# (the hook trap in docs/reference/claude-code-config.md, "A hook symlinked into the repo is branch-fragile").
#
#   install_hal_memory_pull.sh           install (or reinstall) and load the job
#   install_hal_memory_pull.sh --check   report the vault and each section, write nothing
#
# What it does, each step idempotent:
#   1. Checks that ~/Obsidian/scriptorium is a vault (has .obsidian/) and reports, for each
#      section the job writes, whether it exists yet. It creates no vault, section or
#      .obsidian: obsidian-scriptorium's bin/migrate makes each section, and refuses one it
#      didn't place. A missing section is only reported; the job skips it until it exists,
#      and the old vault ~/Obsidian/<vault>/memory is no longer updated once this is loaded.
#   2. Copies the job to ~/Library/Application Support/hal-memory-pull/.
#   3. Writes ~/Library/LaunchAgents/com.dvillavicencio.hal-memory-pull.plist (hourly and
#      at login, log in ~/Library/Logs/hal-memory-pull.log) and (re)loads it. Loading it
#      replaces whatever copy of the job was loaded before (same label).
#
# Undo: launchctl bootout gui/$(id -u)/com.dvillavicencio.hal-memory-pull, then remove
# the plist and the Application Support folder. The sections and the backups in
# ~/.local/state/hal-memory-pull/ stay.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.dvillavicencio.hal-memory-pull"
JOB_SRC="$REPO/helpers/hal_memory_pull.sh"
JOB_DIR="$HOME/Library/Application Support/hal-memory-pull"
JOB="$JOB_DIR/hal-memory-pull.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/hal-memory-pull.log"
VAULT="$HOME/Obsidian/scriptorium"
STATE="$HOME/.local/state/hal-memory-pull"   # the job's default; it stages and backs up there
SSH="${HAL_MEMORY_PULL_SSH:-/usr/bin/ssh}"   # override is for testing
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install $LABEL (job copy at $JOB, plist at $PLIST)"
  exit 0
fi

if [ "$(uname)" != "Darwin" ]; then
  echo "install_hal_memory_pull.sh: personal Mac only; skipping on $(uname)"
  exit 0
fi

# Read-only from here to the ssh check: nothing is created under ~/Obsidian, ever.
if [ -L "$VAULT" ] || [ ! -d "$VAULT/.obsidian" ]; then
  echo "Error: no scriptorium vault at $VAULT (a real folder with .obsidian/); the job writes only into its sections" >&2
  exit 1
fi
# Captured first: a process substitution would drop the exit status of --sections.
sections="$(/bin/sh "$JOB_SRC" --sections)" && [ -n "$sections" ] ||
  { echo "Error: $JOB_SRC --sections failed or listed nothing" >&2; exit 1; }
while read -r section; do
  [ -n "$section" ] || continue
  dir="$VAULT/$section"
  if [ -d "$dir" ] && [ ! -L "$dir" ]; then
    echo "section $section: present ($dir/memory is mirrored from hal)"
  else
    echo "section $section: missing; the job skips it until bin/migrate creates $dir, and ~/Obsidian/$section/memory is no longer updated"
  fi
done < <(printf '%s\n' "$sections")
# The job renames folders between its state dir and the vault, so both must be on one
# volume (it refuses otherwise). Checked on the nearest folder that exists, writing nothing.
probe="$STATE"
while [ ! -e "$probe" ]; do probe="$(dirname "$probe")"; done
if [ "$(/usr/bin/stat -L -f %d "$probe")" != "$(/usr/bin/stat -L -f %d "$VAULT")" ]; then
  echo "Error: $STATE (checked at $probe) is not on the same volume as $VAULT; the job would refuse every run" >&2
  exit 1
fi
[ "$CHECK" = 1 ] && exit 0

if ! "$SSH" -o BatchMode=yes -o ConnectTimeout=10 hal true 2>/dev/null; then
  echo "Error: 'ssh hal' doesn't connect without a prompt; this job needs the hal alias (personal Mac only)" >&2
  exit 1
fi

mkdir -p "$JOB_DIR" "$(dirname "$PLIST")" "$(dirname "$LOG")" || exit 1
tmp="$(mktemp "$JOB_DIR/.job.XXXXXX")" || exit 1
cp "$JOB_SRC" "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$JOB" ||
  { rm -f "$tmp"; echo "Error: cannot install $JOB" >&2; exit 1; }

tmp="$(mktemp "$(dirname "$PLIST")/.$LABEL.XXXXXX")" || exit 1
# printf, not a heredoc: see "No heredocs in bin/dot" in docs/reference/tooling.md.
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0">' \
  '<dict>' \
  "  <key>Label</key><string>$LABEL</string>" \
  '  <key>ProgramArguments</key>' \
  "  <array><string>/bin/sh</string><string>$JOB</string></array>" \
  '  <key>StartInterval</key><integer>3600</integer>' \
  '  <key>RunAtLoad</key><true/>' \
  '  <key>ProcessType</key><string>Background</string>' \
  "  <key>StandardOutPath</key><string>$LOG</string>" \
  "  <key>StandardErrorPath</key><string>$LOG</string>" \
  '</dict>' \
  '</plist>' >"$tmp"
plutil -lint -s "$tmp" && mv -f "$tmp" "$PLIST" ||
  { rm -f "$tmp"; echo "Error: generated plist failed plutil -lint" >&2; exit 1; }

domain="gui/$(id -u)"
launchctl bootout "$domain/$LABEL" 2>/dev/null || true
if ! launchctl bootstrap "$domain" "$PLIST"; then
  echo "Error: launchctl bootstrap failed for $PLIST" >&2
  exit 1
fi
echo "$LABEL loaded; it runs now and hourly. Log: $LOG"
