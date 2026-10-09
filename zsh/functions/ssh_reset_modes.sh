#!/usr/bin/env sh

# ssh — reset terminal modes after every session. A remote TUI (Claude Code,
# vim, tmux) turns on mouse tracking, focus reporting, bracketed paste and the
# kitty keyboard protocol, and turns them off when it exits. A dropped
# connection never delivers that cleanup, so the local shell is left printing
# `[<35;42;17M` on mouse moves and `[I`/`[O` on focus changes. Manual fix:
# `reset`, or iTerm2's Session > Reset.
#
# Only when stdout is a terminal, so `ssh host cmd > file` gets no escapes.
# Leaving the alternate screen (?1049l) also restores the saved cursor, which
# would move the prompt after a clean exit, so it runs only on exit 255
# (ssh's own error: a drop or timeout). zle re-enables bracketed paste at the
# next prompt. Scripts and the herdr shims don't load this function.
function ssh() {
  command ssh "$@"
  local rc=$?
  if [[ -t 1 ]]; then
    # mouse tracking (1000/1002/1003/1006), focus (1004), bracketed paste
    # (2004), pop kitty keyboard flags, show cursor
    printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?2004l\e[<u\e[?25h'
    (( rc == 255 )) && printf '\e[?1049l'
  fi
  return $rc
}
