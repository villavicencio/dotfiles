#!/usr/bin/env sh

# atlas — open the Atlas console on hal in an Orca tab. Atlas is Hermes's
# default profile and runs as the `hal` account. Orca's hal host logs in as
# `david`, so the tab runs `sudo -u hal -i` (one password per visit) into the
# tmux session `atlas` on its own socket. The first visit starts Atlas; later
# visits attach to the same one. When Atlas exits, the window drops to hal's
# shell instead of closing. Closing the tab leaves Atlas running.
#
# On hal as `david` (`ssh hal`, the phone, an Orca tab on hal) `atlas` runs the
# same console command directly. A local `hal` account is the test, not a
# missing `orca`: Orca's tabs on hal put its CLI on PATH too, but that one talks
# to hal's own Orca server, which has no hal-svc environment.
#
# On hal as `hal`, `atlas` is Hermes's own wrapper (`hermes profile alias default --name
# atlas` writes ~/.local/bin/atlas = `hermes -p default`). A function would win
# over it, so this one is only defined where that wrapper doesn't exist (and is
# dropped on a re-source once the wrapper appears).
#
# The hermes workspace is found by path suffix, so no home path is written here.
# ATLAS_ORCA_ENV overrides the Orca environment (default: hal-svc).
if [[ -e "$HOME/.local/bin/atlas" ]]; then
  unfunction atlas 2>/dev/null
  return 0
fi

function atlas() {
  local -a console=(sudo -u hal -i tmux -L atlas new -A -s atlas 'atlas; exec zsh -il')
  if id hal >/dev/null 2>&1; then
    "${console[@]}"
    return
  fi
  command -v orca >/dev/null 2>&1 || { print -u2 -- "atlas: orca is not installed"; return 1; }
  command -v jq >/dev/null 2>&1 || { print -u2 -- "atlas: jq is not installed"; return 1; }
  local env=${ATLAS_ORCA_ENV:-hal-svc} out wt handle
  out=$(orca worktree list --environment "$env" --json 2>&1)
  wt=$(print -r -- "$out" | jq -r '[.result.worktrees[]? | select(.path | endswith("/Projects/hermes"))][0].id // empty' 2>/dev/null)
  [[ -n $wt ]] || { print -u2 -- "atlas: no hermes workspace on Orca environment $env"; print -u2 -r -- "$out"; return 1; }
  out=$(orca terminal create --environment "$env" --worktree "id:$wt" --title Atlas \
    --command "${(j: :)${(@q-)console}}" --focus --json 2>&1)
  handle=$(print -r -- "$out" | jq -r '.result.terminal.handle // empty' 2>/dev/null)
  [[ -n $handle ]] || { print -u2 -- "atlas: Orca didn't open the terminal"; print -u2 -r -- "$out"; return 1; }
  # create can leave the tab in the background; switch brings it forward
  out=$(orca terminal switch --environment "$env" --terminal "$handle" --json 2>&1)
  [[ $(print -r -- "$out" | jq -r '.ok' 2>/dev/null) == true ]] || {
    print -u2 -- "atlas: opened the tab ($handle) but couldn't bring it forward"
    print -u2 -r -- "$out"
    return 1
  }
}
