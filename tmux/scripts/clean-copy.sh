#!/usr/bin/env bash
# Tidy a tmux copy-mode selection, then load it into a tmux buffer and the
# outer terminal's clipboard (OSC 52 via set-clipboard).
#
# Bound from copy-mode-vi on hal (tmux/local.server.conf):
#
#   send-keys -X pipe-no-clear "$HOME/.config/tmux/scripts/clean-copy.sh"
#
# Full-screen TUIs (the Hermes TUI, Claude Code) paint the whole pane, so a raw
# copy brings their layout along. This removes:
#   - the TUI's right-edge scrollbar glyph (│ track, ┃ thumb) when it sits
#     after a run of two or more spaces, the gap that separates the gutter
#     from content;
#   - trailing padding on every line (TUIs fill each line to the pane width);
#   - the shared left margin: the smallest indent of lines 2..n comes off
#     every line, and line 1 (which starts wherever the drag began) loses its
#     leading spaces;
#   - blank lines at the start and end.
# Relative indentation, blank lines inside the text, and box-drawn tables
# (whose right border follows a single space or text) are kept.
#
# Usage: <selection on stdin> | clean-copy.sh
#        clean-copy.sh --print   # filter only: write the result to stdout

set -u

filter() {
  perl -CSD -e '
    my @l = map { s/\r?\n\z//r } <STDIN>;
    for (@l) {
      s/ {2,}[\x{2502}\x{2503}]\s*\z//;   # scrollbar gutter: │ or ┃
      s/\s+\z//;                          # right padding
    }
    shift @l while @l && $l[0] eq "";
    pop @l while @l && $l[-1] eq "";
    exit 0 unless @l;
    my $min;
    for (@l[1 .. $#l]) {
      next if $_ eq "";
      my ($ind) = /^( *)/;
      $min = length $ind if !defined $min || length $ind < $min;
    }
    $min //= 0;
    $l[0] =~ s/^ +//;
    for (@l[1 .. $#l]) { substr($_, 0, $min) = "" if length >= $min }
    print join("\n", @l);
  '
}

if [ "${1:-}" = "--print" ]; then
  filter
  exit
fi

# -w also sends the buffer to the client clipboard (OSC 52, set-clipboard on).
filter | tmux load-buffer -w -
