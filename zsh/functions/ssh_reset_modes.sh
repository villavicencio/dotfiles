#!/usr/bin/env sh

# ssh — reset terminal modes after every session. A remote TUI (Claude Code,
# vim, tmux) turns on mouse tracking, focus reporting, bracketed paste and the
# kitty keyboard protocol, and turns them off when it exits. A dropped
# connection never delivers that cleanup, so the local shell is left printing
# `[<35;42;17M` on mouse moves and `[I`/`[O` on focus changes. Manual fix:
# `reset`, or iTerm2's Session > Reset.
#
# Only when stdout is a terminal, so `ssh host cmd > file` gets no escapes.
# The alternate screen is left with ?1047l, not ?1049l: in iTerm2, 1049l
# always restores the saved cursor, which moves the prompt whenever no
# full-screen program was running (a clean exit, or exit 255 from a failed
# login). 1047l clears and leaves the alternate screen only if it is showing
# and keeps the cursor where it is (VT100Terminal.m), so it is safe every time.
# zle re-enables bracketed paste at the next prompt. Scripts and the herdr
# shims don't load this function.
function ssh() {
  command ssh "$@"
  local rc=$?
  if [[ -t 1 ]]; then
    # mouse tracking (1000/1002/1003/1006), focus (1004), bracketed paste
    # (2004), pop kitty keyboard flags, leave the alternate screen, show cursor
    printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?2004l\e[<u\e[?1047l\e[?25h'
  fi
  return $rc
}
