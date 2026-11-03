#!/usr/bin/env bash
#
# desktop-commander-remote-log-checks.sh — exercise the log rotation in
# helpers/desktop_commander_remote.sh (VIL-579) under a fake HOME. Run by hand after changing
# the job's logging; macOS only (BSD stat, /bin/bash 3.2 like launchd); not in CI.
#
#   ci/desktop-commander-remote-log-checks.sh   exit 0 when every case behaves
#
# Two parts:
#   unit  the job's rotation functions, sourced into /bin/bash with stdout opened O_APPEND
#         on the log, as launchd opens it
#   e2e   the whole job, patched so it can't see or touch a live agent (an OTHER_COPY that
#         matches nothing, a 1 s watch, a 4 KB cap), against a fake package that prints
#         numbered lines fast. Needs Node at NVM_DIR/NODE_VERSION (zshenv); skipped without.
# Cases are eval'd strings, and the job's variables and functions arrive by eval.
# shellcheck disable=SC2016,SC2034,SC2329
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
JOB_SRC="$REPO/helpers/desktop_commander_remote.sh"

if [ "${1:-}" = --unit-child ]; then
  T=$2
  export HOME="$T"
  mkdir -p "$T/Library/Logs" "$T/Library/Application Support/desktop-commander-remote"
  # The job's definitions only: STATE_DIR= through rotate_log_if_due's definition, without
  # the start-up call that follows it.
  eval "$(sed -n '/^STATE_DIR=/,/^rotate_log_if_due$/p' "$JOB_SRC" | sed '$d')"
  LOG_MAX_BYTES=1000; LOG_KEEP=4
  pass=0; fail=0
  ok() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1" >&3; fi; }
  mode() { /usr/bin/stat -f %Lp "$@" | sort -u; }
  size() { /usr/bin/stat -f %z "$1"; }
  age() { echo $(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$1") )); }
  fill() { head -c "$1" /dev/zero | tr '\0' "$2" >>"$LOG"; }
  exec 3>&1 >>"$LOG"
  chmod 600 "$LOG"

  fill 100 x; rotate_log_if_due
  ok "first run: stamp created" '[ -e "$LOG_STAMP" ]'
  ok "first run: no rotation" '[ ! -e "$LOG.1" ]'

  fill 1200 a; rotate_log_if_due
  ok "size: rotated to .1" 'grep -q aaaa "$LOG.1"'
  ok "size: .1 is 600" '[ "$(mode "$LOG.1")" = 600 ]'
  ok "size: log restarted with the rotate line" '[ "$(size "$LOG")" -lt 600 ] && grep -q "log rotated" "$LOG"'
  ok "size: log still 600" '[ "$(mode "$LOG")" = 600 ]'
  echo "after rotation"
  ok "O_APPEND: writes land at the new end, no hole" \
    '[ "$(LC_ALL=C tr -d "\\000" <"$LOG" | wc -c)" -eq "$(size "$LOG")" ] && [ "$(size "$LOG")" -lt 700 ]'

  for c in b c d e f g; do fill 1100 "$c"; rotate_log_if_due; done
  ok "keep: exactly LOG_KEEP copies" '[ -e "$LOG.4" ] && [ ! -e "$LOG.5" ]'
  ok "keep: every copy 600" '[ "$(mode "$LOG".*)" = 600 ]'
  ok "keep: .1 newest, .4 oldest kept" 'grep -q gggg "$LOG.1" && grep -q dddd "$LOG.4"'

  echo "small line"; touch -t 202001010000 "$LOG_STAMP"; rotate_log_if_due
  ok "age: rotated" 'grep -q "small line" "$LOG.1" && grep -q "7 days" "$LOG"'
  ok "age: stamp refreshed" '[ "$(age "$LOG_STAMP")" -lt 5 ]'

  : >"$LOG"; touch -t 202001010000 "$LOG_STAMP"; cp "$LOG.1" "$T/before"; rotate_log_if_due
  ok "age, empty log: no rotation" 'cmp -s "$LOG.1" "$T/before"'
  ok "age, empty log: clock restarted" '[ "$(age "$LOG_STAMP")" -lt 5 ]'

  # Copies left above LOG_KEEP (it was larger once) go at the next rotation.
  echo old >"$LOG.7"; echo old >"$LOG.12"; echo keep >"$LOG.1.bak"; fill 1200 h; rotate_log_if_due
  ok "lowered keep: copies above it deleted" '[ -e "$LOG.4" ] && [ ! -e "$LOG.5" ] && [ ! -e "$LOG.7" ] && [ ! -e "$LOG.12" ]'
  ok "lowered keep: other names left alone" '[ -e "$LOG.1.bak" ]'
  rm -f "$LOG.1.bak"

  # A copy that can't be moved: the chain stops, this log is cleared without a copy.
  cp "$LOG.1" "$T/before"; chflags uchg "$LOG.1"; fill 1200 i; rotate_log_if_due
  ok "move fails: .1 untouched" 'cmp -s "$LOG.1" "$T/before"'
  ok "move fails: log cleared, says why" '[ "$(size "$LOG")" -lt 700 ] && grep -q "without keeping a copy: could not move" "$LOG"'
  chflags nouchg "$LOG.1"

  # A copy that can't be deleted: nothing shifts.
  chflags uchg "$LOG.4"; cp "$LOG.1" "$T/before"; fill 1200 j; rotate_log_if_due
  ok "delete fails: nothing shifted" 'cmp -s "$LOG.1" "$T/before"'
  ok "delete fails: log cleared, says why" '[ "$(size "$LOG")" -lt 700 ] && grep -q "without keeping a copy: could not delete" "$LOG"'
  chflags nouchg "$LOG.4"

  rm -f "$LOG".[0-9]; fill 1200 z; chmod 500 "$T/Library/Logs"; rotate_log_if_due; chmod 700 "$T/Library/Logs"
  ok "copy fails: log cleared anyway" '[ "$(size "$LOG")" -lt 600 ] && grep -q "without keeping a copy: could not write" "$LOG"'

  rm -f "$LOG_STAMP"; chmod 500 "$STATE_DIR"; echo "line"; rotate_log_if_due; rotate_log_if_due
  chmod 700 "$STATE_DIR"
  ok "stamp unwritable: no rotation, age off" '[ ! -e "$LOG.1" ] && grep -q "^line$" "$LOG" && [ "$LOG_BY_AGE" = 0 ]'

  LOG_BY_AGE=1; touch -t 202001010000 "$LOG_STAMP"; chflags uchg "$LOG_STAMP"
  echo "eight-a"; rotate_log_if_due
  ok "stale stamp, locked: rotated once" 'grep -q eight-a "$LOG.1" && grep -q "by size only" "$LOG"'
  echo "eight-b"; rotate_log_if_due
  ok "stale stamp, locked: no second rotation" 'grep -q "^eight-b$" "$LOG" && [ "$LOG_BY_AGE" = 0 ]'
  chflags nouchg "$LOG_STAMP"

  echo "unit: $pass passed, $fail failed" >&3
  [ "$fail" = 0 ]
  exit
fi

T="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'chflags -R nouchg "$T" 2>/dev/null; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
rc=0
/bin/bash "${BASH_SOURCE[0]}" --unit-child "$T/unit" || rc=1

# e2e
eval "$(/bin/zsh -c 'printf "nvm_dir=%q node_version=%q" "$NVM_DIR" "$NODE_VERSION"' 2>/dev/null)"
if [ ! -x "${nvm_dir:-}/versions/node/v${node_version:-}/bin/node" ]; then
  echo "e2e: SKIPPED (no Node at NVM_DIR/NODE_VERSION)"; exit "$rc"
fi
H="$T/e2e"; S="$H/Library/Application Support/desktop-commander-remote"
D="$S/pkg/node_modules/@wonderwhy-er/desktop-commander/dist"
mkdir -p "$H/Library/Logs" "$D" "$H/.desktop-commander-device"
echo '{}' >"$H/.desktop-commander-device/device.json"
printf '%s\n' 'let i = 0; setInterval(() => console.log("line " + (++i) + " " + "x".repeat(60)), 5);' >"$D/index.js"
printf 'export NVM_DIR=%q\nexport NODE_VERSION=%q\n' "$nvm_dir" "$node_version" >"$H/.zshenv"
sed -e "s/^OTHER_COPY=.*/OTHER_COPY='no-such-process-vil579'/" -e 's/^WATCH_SECS=.*/WATCH_SECS=1/' \
    -e 's/^LOG_MAX_BYTES=.*/LOG_MAX_BYTES=4096/' "$JOB_SRC" >"$H/job.sh"
L="$H/Library/Logs/desktop-commander-remote.log"; : >"$L"; chmod 600 "$L"
# Background the job command itself, not a shell function: $! must be the job (HANDOFF gotcha).
env -i HOME="$H" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash "$H/job.sh" >>"$L" 2>&1 </dev/null &
job=$!
sleep 6
kill -TERM "$job"; wait "$job"; jrc=$?
sleep 1
efail=0
check() { if eval "$2"; then :; else efail=1; echo "FAIL: e2e: $1"; fi; }
check "job exits 0 on TERM (got $jrc)" '[ "$jrc" = 0 ]'
check "no package left running" '! /usr/bin/pgrep -f "$D" >/dev/null'
check "rotated at least twice" '[ "$(cat "$L"* | grep -c "log rotated")" -ge 2 ]'
check "LOG_KEEP=2 copies, no third" '[ -e "$L.2" ] && [ ! -e "$L.3" ]'
check "every file 600" '[ "$(/usr/bin/stat -f %Lp "$L"* | sort -u)" = 600 ]'
check "log under the cap plus one watch of output" '[ "$(/usr/bin/stat -f %z "$L")" -lt 12000 ]'
lost=$(cat "$L.2" "$L.1" "$L" | sed -n 's/^line \([0-9]*\) .*/\1/p' |
  awk 'NR > 1 && $1 != p + 1 { n += $1 - p - 1 } { p = $1 } END { print n + 0 }')
echo "e2e: lines lost across rotations: $lost (expected: about one per rotation at this rate)"
[ "$efail" = 0 ] && echo "e2e: passed" || rc=1
exit "$rc"
