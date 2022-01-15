#!/usr/bin/env zsh

# Create a new directory and enter it
function mkdir_and_cd() {
	mkdir -p "$@" && cd "$_" || return;
}
