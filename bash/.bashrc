#!/usr/bin/env bash

# Check if the shell is interactive and source in bash_profile.
[[ -n "$PS1" ]] && source $HOME/.bash_profile;
