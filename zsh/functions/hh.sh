#!/usr/bin/env sh

# hh — history search shortcut (formerly bound to hstr; retired in favor of
# atuin). Drives the same engine as ^R: atuin's interactive search is a ZLE
# widget, so this command shim runs the identical search and loads the chosen
# command onto the next prompt via `print -z` (edit it, or press Enter to run)
# rather than auto-executing — for when you'd rather type `hh` than press ^R.
# Mirrors atuin's own ^R invocation: `atuin search -i` with the 3>&1 1>&2 2>&3
# swap so the TUI draws on the terminal while the selected command is captured.
function hh() {
  command -v atuin >/dev/null 2>&1 || { print -u2 -- "hh: atuin is not installed"; return 1; }
  local _cmd
  _cmd=$(ATUIN_SHELL=zsh ATUIN_LOG=error atuin search -i "$@" 3>&1 1>&2 2>&3) || return
  _cmd=${_cmd#__atuin_accept__:}   # strip atuin's execute-prefix; always load-to-prompt
  [ -n "$_cmd" ] && print -z -- "$_cmd"
}
