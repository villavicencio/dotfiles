#!/usr/bin/env sh

# axiom — open the Axiom console on hal in an Orca tab. Axiom is the Hermes
# profile `axiom` and runs as the `hal` account, like Atlas. The tab opens in
# Orca's axiom project and runs `sudo -u hal -i` (one password per visit) into
# the tmux session `axiom` on its own socket. The first visit starts Axiom in
# the TUI; later visits attach to the same one. When Axiom exits, the window
# drops to hal's shell instead of closing. Closing the tab leaves Axiom running.
#
# On hal as `david`, `axiom` runs the same console command directly. Both paths
# are in _hal_console (hal_console.sh).
#
# If Hermes's own wrapper is there (`hermes profile alias axiom` writes
# ~/.local/bin/axiom, which only the `hal` account would have), it wins and this
# is dropped, as `atlas` is.
#
# AXIOM_ORCA_ENV overrides the Orca environment (default: hal-svc).
if [[ -e "$HOME/.local/bin/axiom" ]]; then
  unfunction axiom 2>/dev/null
  return 0
fi

function axiom() {
  _hal_console axiom Axiom /Projects/axiom "${AXIOM_ORCA_ENV:-hal-svc}" \
    sudo -u hal -i tmux -L axiom new -A -s axiom 'hermes -p axiom --tui; exec zsh -il'
}
