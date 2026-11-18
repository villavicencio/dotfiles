#!/usr/bin/env bash
#
# statusline-checks.sh — feed claude/statusline-command.sh JSON on stdin and assert how the
# ctx meter draws: the hand-off cue (500k, or 80% of a window of 500k or less), the ╎ tick,
# the ┃ compaction mark and the solid fill. Run by hand after changing the script; not in CI.
#
#   ci/statusline-checks.sh        exit 0 when every case passes
#
# Nothing under the real ~/.claude is read or written: HOME and CLAUDE_CONFIG_DIR point at a
# temp directory whose settings.json sets autoCompactWindow 600000. The script runs under
# each of sh and dash that exists, since settings.json starts it with sh and Linux's sh is dash.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$REPO/claude/statusline-command.sh"
T="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/cfg" "$T/cfg-collide"
printf '{"autoCompactWindow": 600000}\n' > "$T/cfg/settings.json"
# autoCompactWindow equal to the 1M cue (500k): the mark and tick want the same cell.
printf '{"autoCompactWindow": 500000}\n' > "$T/cfg-collide/settings.json"

# cells <window|none> <tokens> <shell> [config dir] -> the 20 bar cells as ASCII, one char per cell:
#   S solid fill (U+2588)   f fill (U+2593)   | playhead (U+2502)
#   . track (U+2591)        t hand-off tick (U+254E)   M compaction mark (U+2503)
# Only the ctx meter's line is looked at, so the dir, git and model segments don't matter.
cells() {
  local win="$1" tok="$2" json esc line shell="$3" cfg="${4:-$T/cfg}"
  esc=$'\033'
  if [ "$win" = none ]; then
    json=$(printf '{"model":{"display_name":"M"},"context_window":{"total_input_tokens":%s}}' "$tok")
  else
    json=$(printf '{"model":{"display_name":"M"},"context_window":{"total_input_tokens":%s,"context_window_size":%s}}' "$tok" "$win")
  fi
  line=$(printf '%s' "$json" |
    HOME="$T/home" CLAUDE_CONFIG_DIR="$cfg" "$shell" "$SCRIPT" 2>/dev/null |
    LC_ALL=C sed -e "s/${esc}\\[[0-9;]*m//g" \
      -e $'s/\xe2\x96\x88/S/g' -e $'s/\xe2\x96\x93/f/g' -e $'s/\xe2\x94\x82/|/g' \
      -e $'s/\xe2\x96\x91/./g' -e $'s/\xe2\x95\x8e/t/g' -e $'s/\xe2\x94\x83/M/g' |
    grep 'ctx ' | head -n 1)
  line=${line#*ctx }
  printf '%s' "${line:0:20}"
}

# fillcolor <window> <tokens> <shell> -> the color escape of the ctx bar's first cell (the fill).
fillcolor() {
  local esc json
  esc=$'\033'
  json=$(printf '{"model":{"display_name":"M"},"context_window":{"total_input_tokens":%s,"context_window_size":%s}}' "$2" "$1")
  printf '%s' "$json" | HOME="$T/home" CLAUDE_CONFIG_DIR="$T/cfg" "$3" "$SCRIPT" 2>/dev/null |
    grep 'ctx ' | head -n 1 | sed -n "s/.*ctx ${esc}\\[0m\\(${esc}\\[[0-9;]*m\\).*/\\1/p"
}
# The expected colors come from the script's own ramp(), not hand-typed escapes.
eval "$(sed -n '/^ramp() {/,/^}/p' "$SCRIPT")"
type ramp >/dev/null 2>&1 || { echo "could not load ramp() from $SCRIPT" >&2; exit 1; }

fail=0
# check_color <name> <actual escape> <expected escape> <same|differ>
check_color() {
  local name="$1" got="$2" want="$3" mode="$4" shown ok=0
  shown=${got//$'\033'/ESC}
  if [ -n "$got" ]; then
    if [ "$mode" = same ]; then [ "$got" = "$want" ] && ok=1; else [ "$got" != "$want" ] && ok=1; fi
  fi
  if [ "$ok" = 1 ]; then printf 'ok      %s  [%s]\n' "$name" "$shown"
  else printf 'FAIL    %s  [%s]  (%s %s)\n' "$name" "$shown" "$mode" "${want//$'\033'/ESC}"; fail=1; fi
}
# check <name> <cells> <solid|notsolid> ...: pass when the cells match the predicates given as
# further arguments: solid, notsolid, tick=N, mark=N, notick, nomark, play=N (0-based cells).
check() {
  local name="$1" c="$2" p ok=1 why=""
  shift 2
  if [ "${#c}" != 20 ]; then ok=0; why="no 20-cell ctx bar in the output (got '$c')"; fi
  for p in "$@"; do
    [ "$ok" = 1 ] || break
    case "$p" in
      solid)    [[ "$c" == *S* ]] || { ok=0; why="no solid cell"; } ;;
      notsolid) [[ "$c" != *S* ]] || { ok=0; why="has a solid cell"; } ;;
      tick=*)   [ "${c:${p#tick=}:1}" = t ] || { ok=0; why="no tick at cell ${p#tick=}"; } ;;
      mark=*)   [ "${c:${p#mark=}:1}" = M ] || { ok=0; why="no mark at cell ${p#mark=}"; } ;;
      play=*)   [ "${c:${p#play=}:1}" = '|' ] || { ok=0; why="no playhead at cell ${p#play=}"; } ;;
      notick)   [[ "$c" != *t* ]] || { ok=0; why="a tick is drawn"; } ;;
      nomark)   [[ "$c" != *M* ]] || { ok=0; why="a compaction mark is drawn"; } ;;
    esac
  done
  if [ "$ok" = 1 ]; then printf 'ok      %s  [%s]\n' "$name" "$c"
  else printf 'FAIL    %s  [%s]  %s\n' "$name" "$c" "$why"; fail=1; fi
}

SHELLS=()
for s in sh dash; do command -v "$s" >/dev/null 2>&1 && SHELLS+=("$s"); done
[ "${#SHELLS[@]}" -gt 0 ] || { echo "no sh found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

for sh_ in "${SHELLS[@]}"; do
  echo "== run under $sh_"
  # Cells for a 1M window with autoCompactWindow 600000, from the script's rounding
  # (point * 20 + win / 2) / win: the 500k cue is cell (10000000 + 500000) / 1000000 = 10, the
  # 600k mark is cell (12000000 + 500000) / 1000000 = 12. For a 200k window the 160k cue is
  # cell (3200000 + 100000) / 200000 = 16. At exactly the cue the playhead sits on the tick's
  # cell and covers it, so the tick is asserted at a lower token count.
  check "1M window, 499,999 tokens: fill is not solid" "$(cells 1000000 499999 "$sh_")" notsolid
  check "1M window, 500,000 tokens: fill is solid"     "$(cells 1000000 500000 "$sh_")" solid
  check "1M window, 100,000 tokens: tick in cell 10, mark in cell 12 (different cells)" \
    "$(cells 1000000 100000 "$sh_")" notsolid tick=10 mark=12
  check "200k window, 159,999 tokens: fill is not solid" "$(cells 200000 159999 "$sh_")" notsolid
  check "200k window, 160,000 tokens: fill is solid (cue is 80% of the window)" \
    "$(cells 200000 160000 "$sh_")" solid play=16
  check "200k window, 100,000 tokens: tick draws in cell 16, inside the bar, no mark" \
    "$(cells 200000 100000 "$sh_")" notsolid tick=16 nomark
  check "500k window, 399,999 tokens: fill is not solid" "$(cells 500000 399999 "$sh_")" notsolid
  check "500k window, 400,000 tokens: fill is solid (80% applies up to 500k)" \
    "$(cells 500000 400000 "$sh_")" solid
  check "600k window, 499,999 tokens: fill is not solid (500k cue above 500k)" \
    "$(cells 600000 499999 "$sh_")" notsolid
  check "600k window, 500,000 tokens: fill is solid" "$(cells 600000 500000 "$sh_")" solid
  check "1M window, autoCompactWindow 500000: mark in cell 10, tick steps to cell 9 (both show)" \
    "$(cells 1000000 100000 "$sh_" "$T/cfg-collide")" notsolid tick=9 mark=10
  # Colors on a 200k window (cue 160k): full yellow is ramp 1000 (permille of the cue). At
  # 100,000 tokens the fill is 625 permille of the cue, so it must be ramp 625 and not full
  # yellow; a ramp still keyed to 500k would give 200 permille there and 320 at 160,000.
  check_color "200k window, 160,000 tokens: fill color is full yellow (ramp 1000)" \
    "$(fillcolor 200000 160000 "$sh_")" "$(ramp 1000)" same
  check_color "200k window, 100,000 tokens: fill color is ramp 625, not full yellow" \
    "$(fillcolor 200000 100000 "$sh_")" "$(ramp 625)" same
  check_color "200k window, 100,000 tokens: fill color differs from full yellow" \
    "$(fillcolor 200000 100000 "$sh_")" "$(ramp 1000)" differ
  check "no window, 100,000 tokens: no tick, no compaction mark" \
    "$(cells none 100000 "$sh_")" notsolid notick nomark
  check "no window, 500,000 tokens: solid fill, still no tick or mark" \
    "$(cells none 500000 "$sh_")" solid notick nomark
done

echo
if [ "$fail" = 0 ]; then echo "all statusline checks passed"; else echo "statusline checks FAILED"; fi
exit "$fail"
