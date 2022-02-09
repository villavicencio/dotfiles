#!/usr/bin/env sh

# Determine size of a file or total size of a directory
function size_of_file_or_directory() {
	if du -b /dev/null > /dev/null 2>&1; then
		local arg=-sbh;
	else
		local arg=-sh;
	fi
	if [[ -n "$*" ]]; then
		du $arg -- "$@";
	else
		du $arg .[^.]* -- *;
	fi;
}
