#!/usr/bin/env bash

# With no arguments, opens the current directory in Sublime Text, otherwise opens the given location
function open_with_sublime() {
	if [[ $# -eq 0 ]]; then
		subl .;
	else
		subl "$@";
	fi;
}
