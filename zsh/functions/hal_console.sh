#!/usr/bin/env sh

# _hal_console — the shared body of `atlas` and `axiom`, the Hermes agents that
# run as hal's `hal` account. Usage:
#
#   _hal_console <name> <tab title> <project path suffix> <Orca environment> <console command...>
#
# On a desk Mac it opens the console command in a new Orca tab, in the workspace
# on <Orca environment> whose path ends in <project path suffix>, and brings the
# tab forward. On hal as `david` (`ssh hal`, the phone, an Orca tab on hal) it
# runs the console command in place. A local `hal` account is the test, not a
# missing `orca`: Orca's tabs on hal put its CLI on PATH too, but that one talks
# to hal's own Orca server, which has no hal-svc environment.
#
# Workspaces are found by path suffix, so no home path is written here.
function _hal_console() {
  local name=$1 title=$2 suffix=$3 env=$4
  shift 4
  local -a console=("$@")
  if id hal >/dev/null 2>&1; then
    "${console[@]}"
    return
  fi
  command -v orca >/dev/null 2>&1 || { print -u2 -- "$name: orca is not installed"; return 1; }
  command -v jq >/dev/null 2>&1 || { print -u2 -- "$name: jq is not installed"; return 1; }
  local out wt handle
  out=$(orca worktree list --environment "$env" --json 2>&1)
  wt=$(print -r -- "$out" | jq -r --arg s "$suffix" '[.result.worktrees[]? | select(.path | endswith($s))][0].id // empty' 2>/dev/null)
  [[ -n $wt ]] || { print -u2 -- "$name: no workspace ending in $suffix on Orca environment $env"; print -u2 -r -- "$out"; return 1; }
  out=$(orca terminal create --environment "$env" --worktree "id:$wt" --title "$title" \
    --command "${(j: :)${(@q-)console}}" --focus --json 2>&1)
  handle=$(print -r -- "$out" | jq -r '.result.terminal.handle // empty' 2>/dev/null)
  [[ -n $handle ]] || { print -u2 -- "$name: Orca didn't open the terminal"; print -u2 -r -- "$out"; return 1; }
  # create can leave the tab in the background; switch brings it forward
  out=$(orca terminal switch --environment "$env" --terminal "$handle" --json 2>&1)
  [[ $(print -r -- "$out" | jq -r '.ok' 2>/dev/null) == true ]] || {
    print -u2 -- "$name: opened the tab ($handle) but couldn't bring it forward"
    print -u2 -r -- "$out"
    return 1
  }
}
