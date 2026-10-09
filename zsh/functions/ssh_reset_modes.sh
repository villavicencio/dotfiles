#!/usr/bin/env sh

# ssh — reset terminal modes after every session. A remote TUI (Claude Code,
# vim, tmux) turns on mouse tracking, focus reporting, bracketed paste and the
# kitty keyboard protocol, and turns them off when it exits. A dropped
# connection never delivers that cleanup, so the local shell is left printing
# `[<35;42;17M` on mouse moves and `[I`/`[O` on focus changes. Manual fix:
# `reset`, or iTerm2's Session > Reset.
#
# Only when stdout is a terminal, so `ssh host cmd > file` gets no escapes.
# The alternate screen is left with \e7 then ?1049l. iTerm2 keeps one saved
# cursor per screen, and 1049l restores the main screen's (VT100Terminal.m,
# savedCursor and case 1049). After a drop inside a full-screen program, \e7
# lands in the alternate screen's slot, so 1049l puts the cursor back where
# the program's 1049h saved it. On the main screen, \e7 saves the current
# position and 1049l restores that same position, so nothing moves. Plain
# 1049l would move the prompt when no full-screen program ran (a clean exit,
# a failed login); plain 1047l would leave it wherever the program's cursor was.
# zle re-enables bracketed paste at the next prompt. Scripts and the herdr
# shims don't load this function.
function ssh() {
  command ssh "$@"
  local rc=$?
  if [[ -t 1 ]]; then
    # mouse tracking (1000/1002/1003/1006), focus (1004), bracketed paste
    # (2004), pop kitty keyboard flags, leave the alternate screen, show cursor
    printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?2004l\e[<u\e7\e[?1049l\e[?25h'
  fi
  return $rc
}
