#!/usr/bin/env zsh

# Run `dig` and display the most useful info
function digga() {
	dig +nocmd "$1" any +multiline +noall +answer;
}

# `tre` is a shorthand for `tree` with hidden files and color enabled, ignoring
# the `.git` directory, listing directories first. The output gets piped into
# `less` with options to preserve color and line numbers, unless the output is
# small enough for one screen.
function tre() {
	tree -aC -I '.git|node_modules|bower_components' --dirsfirst "$@" | less -FRNX;
}

# List the files with case-sensitive globbing, whatever the interactive options say: with
# NO_CASE_GLOB (zshrc) zsh reads every directory on the path to match it, and `hal` on hal can
# only search, not read, the home `david`'s clone sits in (VIL-700).
() { setopt localoptions case_glob; reply=("$DOTFILES/zsh/functions"/*.sh) }
for function in "${reply[@]}"; do . "${function}"; done
unset function reply
