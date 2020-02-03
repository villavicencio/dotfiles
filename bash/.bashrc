#!/usr/bin/env bash

# Ignore shellcheck errors for sourced files
# shellcheck source=/dev/null

# Check if the shell is interactive and source in bash_profile.
[[ -n "$PS1" ]] && source "$HOME/.bash_profile";

# Created by `userpath` on 2020-02-02 22:13:33
export PATH="$PATH:/Users/david/.local/bin"
