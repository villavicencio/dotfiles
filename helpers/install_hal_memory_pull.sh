#!/usr/bin/env bash
#
# install_hal_memory_pull.sh — install the LaunchAgent that mirrors Claude Code memory
# from hal into Obsidian vaults (helpers/hal_memory_pull.sh explains the job itself).
#
# Personal Mac only, run by hand; ./install doesn't call it, because the work Mac has no
# `hal` alias. Re-run it after changing hal_memory_pull.sh: the job runs from a copy, so
# a branch switch in this repo can't leave the LaunchAgent pointing at a missing file
# (the hook trap in CLAUDE.md, "A hook symlinked into the repo is branch-fragile").
#
# What it does, each step idempotent:
#   1. Bootstraps each vault the job writes to: ~/Obsidian/<vault>/, with the standard
#      config from obsidian/vault-template/ when it has no .obsidian yet.
#   2. Copies the job to ~/Library/Application Support/hal-memory-pull/.
#   3. Writes ~/Library/LaunchAgents/com.dvillavicencio.hal-memory-pull.plist (hourly and
#      at login, log in ~/Library/Logs/hal-memory-pull.log) and (re)loads it.
#
# Undo: launchctl bootout gui/$(id -u)/com.dvillavicencio.hal-memory-pull, then remove
# the plist and the Application Support folder. The vaults and their backups stay.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.dvillavicencio.hal-memory-pull"
JOB_SRC="$REPO/helpers/hal_memory_pull.sh"
JOB_DIR="$HOME/Library/Application Support/hal-memory-pull"
JOB="$JOB_DIR/hal-memory-pull.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/hal-memory-pull.log"
TEMPLATE="$REPO/obsidian/vault-template/.obsidian"

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install $LABEL (job copy at $JOB, plist at $PLIST)"
  exit 0
fi

if [ "$(uname)" != "Darwin" ]; then
  echo "install_hal_memory_pull.sh: personal Mac only; skipping on $(uname)"
  exit 0
fi

if ! /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 hal true 2>/dev/null; then
  echo "Error: 'ssh hal' doesn't connect without a prompt; this job needs the hal alias (personal Mac only)" >&2
  exit 1
fi

while read -r vault; do
  [ -n "$vault" ] || continue
  dir="$HOME/Obsidian/$vault"
  mkdir -p "$dir" || { echo "Error: cannot create $dir" >&2; exit 1; }
  if [ ! -e "$dir/.obsidian" ]; then
    cp -R "$TEMPLATE" "$dir/.obsidian" || { echo "Error: cannot stamp $dir/.obsidian" >&2; exit 1; }
    echo "vault $vault: created with the standard config"
  else
    echo "vault $vault: exists"
  fi
done < <(/bin/sh "$JOB_SRC" --vaults)

mkdir -p "$JOB_DIR" "$(dirname "$PLIST")" "$(dirname "$LOG")" || exit 1
tmp="$(mktemp "$JOB_DIR/.job.XXXXXX")" || exit 1
cp "$JOB_SRC" "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$JOB" ||
  { rm -f "$tmp"; echo "Error: cannot install $JOB" >&2; exit 1; }

tmp="$(mktemp "$(dirname "$PLIST")/.$LABEL.XXXXXX")" || exit 1
# printf, not a heredoc: see "No heredocs in bin/dot" in CLAUDE.md.
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
