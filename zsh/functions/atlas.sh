#!/usr/bin/env sh

# atlas — open the Atlas console on hal in an Orca tab. Atlas is Hermes's
# default profile and runs as the `hal` account. Orca's hal host logs in as
# `david`, so the tab runs `sudo -u hal -i` (one password per visit) into the
# tmux session `atlas` on its own socket. The first visit starts Atlas; later
# visits attach to the same one. When Atlas exits, the window drops to hal's
# shell instead of closing. Closing the tab leaves Atlas running.
#
# The tab opens in Orca's hermes project. On hal as `david`, `atlas` runs the
# same console command directly. Both paths are in _hal_console (hal_console.sh).
#
# On hal as `hal`, `atlas` is Hermes's own wrapper (`hermes profile alias default --name
# atlas` writes ~/.local/bin/atlas = `hermes -p default`). A function would win
# over it, so this one is only defined where that wrapper doesn't exist (and is
# dropped on a re-source once the wrapper appears).
#
# ATLAS_ORCA_ENV overrides the Orca environment (default: hal-svc).
if [[ -e "$HOME/.local/bin/atlas" ]]; then
  unfunction atlas 2>/dev/null
  return 0
fi

function atlas() {
  _hal_console atlas Atlas /Projects/hermes "${ATLAS_ORCA_ENV:-hal-svc}" \
    sudo -u hal -i tmux -L atlas new -A -s atlas 'atlas; exec zsh -il'
}
