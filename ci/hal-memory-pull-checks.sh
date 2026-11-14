#!/usr/bin/env bash
#
# hal-memory-pull-checks.sh — exercise helpers/hal_memory_pull.sh (the job) and
# helpers/install_hal_memory_pull.sh (its installer) on temp folders (VIL-721). Run by hand
# after changing either; macOS only (BSD stat, lockf, /bin/sh as launchd runs it); not in CI.
#
#   ci/hal-memory-pull-checks.sh   exit 0 when every case behaves
#
# Nothing here reaches hal, ~/Obsidian, ~/.local/state, ~/Library or launchd:
#   - the job gets a fake ssh (HAL_MEMORY_PULL_SSH) that runs the remote command in a temp
#     "remote home", and temp HAL_MEMORY_PULL_OBSIDIAN / HAL_MEMORY_PULL_STATE;
#   - the installer runs under a fake HOME with the same fake ssh and a stub launchctl first
#     on PATH. The script stops before any installer run unless `launchctl` resolves to the
#     stub, because the real one would boot out the live job (same label).
# Cases are eval'd strings, so shellcheck sees their variables as unused.
# shellcheck disable=SC2016,SC2034
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
JOB_SRC="$REPO/helpers/hal_memory_pull.sh"
INSTALLER="$REPO/helpers/install_hal_memory_pull.sh"

T="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
T="$(cd "$T" && pwd -P)"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT

pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

# --- stubs ------------------------------------------------------------------------------
STUB="$T/stub"; mkdir -p "$STUB"
printf '%s\n' '#!/bin/sh' \
  '# Fake ssh: drop options, take the host, run the command in $FAKE_REMOTE_HOME.' \
  'while [ $# -gt 0 ]; do case $1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done' \
  'host=$1; shift' \
  'if [ -n "${FAKE_SSH_FAIL:-}" ]; then' \
  '  echo "ssh: connect to host $host port 22: Operation timed out" >&2; exit 255' \
  'fi' \
  'cd "$FAKE_REMOTE_HOME" || exit 255' \
  'exec /bin/sh -c "$*"' >"$STUB/ssh"
printf '%s\n' '#!/bin/sh' 'echo "launchctl $*" >>"$LAUNCHCTL_LOG"' >"$STUB/launchctl"
chmod 755 "$STUB/ssh" "$STUB/launchctl"
export FAKE_REMOTE_HOME="$T/remote" LAUNCHCTL_LOG="$T/launchctl.log"

# --- the job ----------------------------------------------------------------------------
OB="$T/Obsidian"; ST="$T/state"; SCR="$OB/scriptorium"
REM="$FAKE_REMOTE_HOME/.claude/projects"
OUT="$T/job.out"
PROJ='
-Users-david-Projects-skills skills
-Users-david-Projects-bryancola-com bryancola
'
job() { # runs the job as launchd does; output in $OUT, status in $jrc
  HAL_MEMORY_PULL_SSH="$STUB/ssh" HAL_MEMORY_PULL_HOST=fakehal.invalid HAL_MEMORY_PULL_PROJECTS="$PROJ" \
    HAL_MEMORY_PULL_OBSIDIAN="$OB" HAL_MEMORY_PULL_STATE="$ST" \
    /bin/sh "$JOB_SRC" "$@" >"$OUT" 2>&1
  jrc=$?
}
tree() { (cd "$1" && find . | LC_ALL=C sort); }
# Every path under the Obsidian root with its size, mtime and mode: any write shows.
obsnap() { (cd "$OB" && find . -exec /usr/bin/stat -f '%N %z %m %p' {} + | LC_ALL=C sort); }
hidden_in_scr() { (cd "$SCR" && find . -mindepth 2 -name '.*' ! -path './.obsidian*' | grep -c .); }

mkdir -p "$REM/-Users-david-Projects-skills/memory" "$REM/-Users-david-Projects-bryancola-com/memory"
echo one >"$REM/-Users-david-Projects-skills/memory/MEMORY.md"
echo b1 >"$REM/-Users-david-Projects-bryancola-com/memory/MEMORY.md"
# An old-style vault with its own mirror and backups, which the job must never touch again.
mkdir -p "$OB/skills/memory" "$OB/skills/.obsidian" "$OB/skills/.sync-backup/20261103T235236Z.1LGO/memory"
echo old >"$OB/skills/memory/MEMORY.md"

job --sections
ok "--sections lists the section names" '[ "$(cat "$OUT")" = "$(printf "skills\nbryancola")" ]'

before=$(obsnap)
DOTFILES_DRY_RUN=1 job
ok "dry run: exit 0, says so" '[ "$jrc" = 0 ] && grep -q "dry-run" "$OUT"'
ok "dry run: nothing written" '[ "$(obsnap)" = "$before" ] && [ ! -e "$ST" ]'

job
ok "no scriptorium vault: exit 1, says so" '[ "$jrc" = 1 ] && grep -q "no scriptorium vault" "$OUT"'
ok "no scriptorium vault: nothing written under Obsidian" '[ "$(obsnap)" = "$before" ]'

mkdir -p "$SCR/.obsidian"; echo '{}' >"$SCR/.obsidian/app.json"
before=$(obsnap)
job
ok "sections missing: exit 0, one line per section" \
  '[ "$jrc" = 0 ] && [ "$(grep -c "no section at" "$OUT")" = 2 ]'
ok "sections missing: no section, .partial or .obsidian created; nothing written" \
  '[ "$(obsnap)" = "$before" ]'
ok "sections missing: no lock or stage left in the Obsidian root" \
  '[ ! -e "$OB/.hal-memory-pull.flock" ] && [ -z "$(ls -A "$ST/stage" 2>/dev/null)" ]'

mkdir "$SCR/skills.partial"
before=$(obsnap)
job
ok "only skills.partial: skipped, the partial copy untouched" \
  '[ "$jrc" = 0 ] && grep -q "skills: no section at" "$OUT" && [ "$(obsnap)" = "$before" ]'
rmdir "$SCR/skills.partial"

mkdir "$T/elsewhere"; ln -s "$T/elsewhere" "$SCR/skills"
job
ok "section is a symlink: not followed, exit 1" \
  '[ "$jrc" = 1 ] && grep -q "skills: .* is a symlink" "$OUT" && [ -z "$(ls -A "$T/elsewhere")" ]'
rm "$SCR/skills"

mkdir "$SCR/skills"; echo note >"$SCR/skills/note.md"
oldvault=$(cd "$OB/skills" && find . -exec /usr/bin/stat -f '%N %z %m' {} + | LC_ALL=C sort)
job
ok "first pull: exit 0, memory created in the section" \
  '[ "$jrc" = 0 ] && [ "$(cat "$SCR/skills/memory/MEMORY.md")" = one ] && grep -q "skills: updated from fakehal.invalid$" "$OUT"'
ok "first pull: the rest of the section untouched" '[ "$(cat "$SCR/skills/note.md")" = note ]'
ok "first pull: bryancola still skipped" '[ ! -e "$SCR/bryancola" ] && grep -q "bryancola: no section at" "$OUT"'
ok "first pull: no hidden file or folder inside the vault" '[ "$(hidden_in_scr)" = 0 ]'
ok "first pull: no backup made" '[ -z "$(ls -A "$ST/backups/skills" 2>/dev/null)" ]'

job
ok "unchanged: exit 0, no line for skills, no backup" \
  '[ "$jrc" = 0 ] && ! grep -q "^.* skills:" "$OUT" && [ -z "$(ls -A "$ST/backups/skills" 2>/dev/null)" ]'

echo two >"$REM/-Users-david-Projects-skills/memory/MEMORY.md"
job
bk=$(ls -d "$ST"/backups/skills/*/ 2>/dev/null | head -1)
ok "changed on hal: section updated" '[ "$jrc" = 0 ] && [ "$(cat "$SCR/skills/memory/MEMORY.md")" = two ]'
ok "changed on hal: previous copy kept in the state dir, named in the log" \
  '[ -n "$bk" ] && [ "$(cat "$bk/memory/MEMORY.md")" = one ] && grep -q "previous copy in $ST/backups/skills/" "$OUT"'
ok "changed on hal: still no hidden item inside the vault" '[ "$(hidden_in_scr)" = 0 ]'

echo edited >>"$SCR/skills/memory/MEMORY.md"
job
ok "edit in the section: replaced, second backup kept" \
  '[ "$(cat "$SCR/skills/memory/MEMORY.md")" = two ] && [ "$(ls "$ST/backups/skills" | wc -l | tr -d " ")" = 2 ]'

ok "old vault untouched throughout" \
  '[ "$(cd "$OB/skills" && find . -exec /usr/bin/stat -f "%N %z %m" {} + | LC_ALL=C sort)" = "$oldvault" ]'

snap_sec=$(tree "$SCR/skills"); FAKE_SSH_FAIL=1 job
ok "hal unreachable: exit 1, logged, section untouched" \
  '[ "$jrc" = 1 ] && grep -q "skills: pull failed (ssh 255)" "$OUT" && [ "$(tree "$SCR/skills")" = "$snap_sec" ]'
ok "hal unreachable: no stage left behind" '[ -z "$(ls -A "$ST/stage")" ]'

mv "$REM/-Users-david-Projects-skills/memory" "$T/remote-mem"
job
ok "folder missing on hal: section left alone" \
  '[ "$jrc" = 0 ] && grep -q "skills: fakehal.invalid:.* is missing" "$OUT" && [ "$(cat "$SCR/skills/memory/MEMORY.md")" = two ]'
mkdir "$REM/-Users-david-Projects-skills/memory"
job
ok "folder empty on hal: section left alone" \
  '[ "$jrc" = 0 ] && grep -q "skills: fakehal.invalid:.* is empty" "$OUT" && [ "$(cat "$SCR/skills/memory/MEMORY.md")" = two ]'
rmdir "$REM/-Users-david-Projects-skills/memory"; mv "$T/remote-mem" "$REM/-Users-david-Projects-skills/memory"

mv "$SCR/skills/memory" "$T/realmem"; ln -s "$T/realmem" "$SCR/skills/memory"
echo three >"$REM/-Users-david-Projects-skills/memory/MEMORY.md"
job
ok "memory/ is a symlink: refused, exit 1, link and target untouched" \
  '[ "$jrc" = 1 ] && grep -q "skills: .*memory is a symlink" "$OUT" && [ -L "$SCR/skills/memory" ] && [ "$(cat "$T/realmem/MEMORY.md")" = two ]'
rm "$SCR/skills/memory"; mv "$T/realmem" "$SCR/skills/memory"

mkdir "$SCR/bryancola"
job
ok "both sections: both updated" \
  '[ "$jrc" = 0 ] && [ "$(cat "$SCR/skills/memory/MEMORY.md")" = three ] && [ "$(cat "$SCR/bryancola/memory/MEMORY.md")" = b1 ]'
ok "lock lives in the state dir" '[ -e "$ST/run.flock" ] && [ ! -e "$OB/.hal-memory-pull.flock" ]'

# A second run while one holds the lock skips at once.
/usr/bin/lockf -k -s -t 0 "$ST/run.flock" /bin/sh -c 'sleep 3' & lp=$!
sleep 1; job; wait "$lp"
ok "lock held: exit 0, skipped" '[ "$jrc" = 0 ] && grep -q "another run holds" "$OUT"'

# --- the installer ----------------------------------------------------------------------
H="$T/home"; mkdir -p "$H"
inst() { # runs the installer under the fake HOME; output in $OUT, status in $irc
  HOME="$H" PATH="$STUB:$PATH" HAL_MEMORY_PULL_SSH="$STUB/ssh" /bin/bash "$INSTALLER" "$@" >"$OUT" 2>&1
  irc=$?
}
if [ "$(PATH="$STUB:$PATH" command -v launchctl)" != "$STUB/launchctl" ]; then
  echo "ABORT: launchctl does not resolve to the stub; not running the installer cases"; exit 1
fi
hsnap() { (cd "$H" && find . -exec /usr/bin/stat -f '%N %z %m %p' {} + | LC_ALL=C sort); }

inst
ok "install, no scriptorium vault: refused, nothing written" \
  '[ "$irc" = 1 ] && grep -q "no scriptorium vault" "$OUT" && [ -z "$(ls -A "$H")" ] && [ ! -e "$LAUNCHCTL_LOG" ]'

mkdir -p "$H/Obsidian/scriptorium/.obsidian" "$H/Obsidian/scriptorium/skills"
before=$(hsnap)
inst --check
ok "--check: exit 0, reports each section" \
  '[ "$irc" = 0 ] && grep -q "section skills: present" "$OUT" && grep -q "section bryancola: missing" "$OUT"'
ok "--check: nothing written, launchctl not called" '[ "$(hsnap)" = "$before" ] && [ ! -e "$LAUNCHCTL_LOG" ]'

DOTFILES_DRY_RUN=1 inst
ok "install dry run: nothing written" '[ "$irc" = 0 ] && [ "$(hsnap)" = "$before" ] && [ ! -e "$LAUNCHCTL_LOG" ]'

FAKE_SSH_FAIL=1 inst
ok "install, hal unreachable: refused before any write" \
  '[ "$irc" = 1 ] && [ "$(hsnap)" = "$before" ] && [ ! -e "$LAUNCHCTL_LOG" ]'

obs_before=$(cd "$H/Obsidian" && find . | LC_ALL=C sort)
inst
JOBCOPY="$H/Library/Application Support/hal-memory-pull/hal-memory-pull.sh"
PL="$H/Library/LaunchAgents/com.dvillavicencio.hal-memory-pull.plist"
ok "install: exit 0, job copied as is" '[ "$irc" = 0 ] && cmp -s "$JOBCOPY" "$JOB_SRC"'
ok "install: plist valid and points at the copy" 'plutil -lint -s "$PL" && grep -q "hal-memory-pull/hal-memory-pull.sh" "$PL"'
ok "install: launchctl bootout then bootstrap" \
  '[ "$(cut -d" " -f2 "$LAUNCHCTL_LOG" | tr "\n" " ")" = "bootout bootstrap " ]'
ok "install: nothing created under Obsidian (no vault, section or .obsidian)" \
  '[ "$(cd "$H/Obsidian" && find . | LC_ALL=C sort)" = "$obs_before" ]'
ok "install: warns that bryancola is not mirrored yet" 'grep -q "section bryancola: missing" "$OUT"'

echo "hal-memory-pull checks: $pass passed, $fail failed"
[ "$fail" = 0 ]
