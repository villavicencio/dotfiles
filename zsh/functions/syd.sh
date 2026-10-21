#!/usr/bin/env sh

# syd — start Syd, the Hermes profile `syd` that lives only on the personal
# Mac, in the TUI. Arguments pass through, so `syd -c` continues the last
# session, `syd -r <id>` resumes one, and `syd sessions list` lists them
# (Hermes ignores --tui for subcommands).
#
# Only defined where the `syd` profile exists, so hal and the work Mac don't get
# a command that can only fail. If Hermes's own wrapper is there (`hermes profile
# alias syd` writes ~/.local/bin/syd), it wins and this is dropped, as `atlas` is.
if [[ ! -d "$HOME/.hermes/profiles/syd" || -e "$HOME/.local/bin/syd" ]]; then
  unfunction syd 2>/dev/null
  return 0
fi

function syd() {
  hermes -p syd --tui "$@"
}
