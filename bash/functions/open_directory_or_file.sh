#!/usr/bin/env bash

# With no arguments, opens the current directory, otherwise opens the given location
function open_directory_or_file() {
    if [[ $# -eq 0 ]]; then
		open .;
	else
		open "$@";
	fi;
}
