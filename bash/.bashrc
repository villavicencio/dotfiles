#!/usr/bin/env bash

# Ignore shellcheck errors for sourced files
# shellcheck source=/dev/null

# Check if the shell is interactive and source in bash_profile.
[[ -n "$PS1" ]] && source "$HOME/.bash_profile";
