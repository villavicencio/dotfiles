#!/usr/bin/env bash
# Tidy a tmux copy-mode selection, then load it into a tmux buffer and the
# outer terminal's clipboard (OSC 52 via set-clipboard).
#
# Bound from copy-mode-vi on hal (tmux/local.server.conf):
#
#   send-keys -X pipe-no-clear "$HOME/.config/tmux/scripts/clean-copy.sh #{selection_start_x} #{selection_start_y} #{selection_end_x} #{selection_end_y} #{rectangle_toggle}"
#
# pipe-no-clear, not copy-pipe-no-clear: it pipes the selection without copying
# it to a buffer first, because this script loads the buffer itself. Both are
# tmux copy-mode commands (`man tmux`). tmux expands the #{...} formats in the
# pipe command (checked on tmux 3.7c), so the script knows the screen column
# where the selection's first line begins.
#
# Full-screen TUIs (the Hermes TUI, Claude Code) paint the whole pane, so a raw
# copy brings their layout along. This removes:
#   - the TUI's right-edge scrollbar glyph (│ track, ┃ thumb) when it sits
#     after a run of two or more spaces. A line whose text starts with a
#     box-drawing character is a table or box row, and keeps its right border;
#   - trailing padding on every line (TUIs fill each line to the pane width);
#   - the shared left margin. Each line's indent is measured in screen columns
#     (the first line starts at the selection's start column), and the
#     smallest one comes off every line, so relative indentation is kept.
#     The first line gains spaces only when it starts no further right than
#     the deepest indent below it, so a drag that starts mid-sentence doesn't
#     paste the columns before it as indent;
#   - blank lines at the start and end.
# Limits: a first-line table row whose left border lies before the selection
# start loses its right border, and a tab counts as one column. Without the
# position arguments (--print by hand), the first line is taken to start at
# column 0.
#
# Usage: <selection on stdin> | clean-copy.sh [sx sy ex ey rect]
#        clean-copy.sh --print [sx sy ex ey rect]   # filter only, to stdout

set -u

filter() {
  perl -CSD -e '
    my ($sx, $sy, $ex, $ey, $rect) = @ARGV;
    # Screen column where the first selected line begins. A rectangle starts
    # every line at the same column, so only a normal selection offsets line 1.
    my $x0 = 0;
    if (@ARGV == 5 && !grep { !/\A\d+\z/ } @ARGV and !$rect) {
      $x0 = $sy < $ey ? $sx : $sy > $ey ? $ex : ($sx < $ex ? $sx : $ex);
    }
    my @l = map { s/\r?\n\z//r } <STDIN>;
    for (@l) {
      s/ {2,}[\x{2502}\x{2503}]\s*\z// unless /^\s*[\x{2500}-\x{257F}]/;  # scrollbar: │ or ┃
      s/\s+\z//;                                                          # right padding
    }
    while (@l && $l[0] eq "") { shift @l; $x0 = 0 }   # the new first line starts at column 0
    pop @l while @l && $l[-1] eq "";
    exit 0 unless @l;
    my $min;
    for my $i (0 .. $#l) {
      next if $l[$i] eq "";
      my ($ind) = $l[$i] =~ /^( *)/;
      my $col = length($ind) + ($i == 0 ? $x0 : 0);
      $min = $col if !defined $min || $col < $min;
    }
    # Line 1 keeps its column relative to the margin, but gains spaces only
    # when it starts no further right than the deepest indent below it: a
    # drag that starts mid-sentence must not paste the columns before it.
    my ($ind0) = $l[0] =~ /^( *)/;
    my $deepest = 0;
    for (@l[1 .. $#l]) { my ($i) = /^( *)/; $deepest = length $i if $_ ne "" && length $i > $deepest }
    my $keep = length($ind0) + $x0 - $min;
    $keep = 0 if $keep < 0;
    $keep = length($ind0) if $keep > length($ind0) && length($ind0) + $x0 > $deepest;
    $l[0] =~ s/^ */" " x $keep/e;
    for (@l[1 .. $#l]) { substr($_, 0, $min) = "" if length >= $min }
    print join("\n", @l);
  ' -- "$@"
}

if [ "${1:-}" = "--print" ]; then
  shift
  filter "$@"
  exit
fi

# -w also sends the buffer to the client clipboard (OSC 52, set-clipboard on).
filter "$@" | tmux load-buffer -w -
