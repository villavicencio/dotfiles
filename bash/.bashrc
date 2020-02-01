#!/usr/bin/env bash

# Check if the shell is interactive and source in bash_profile.
[[ -n "$PS1" ]] && source $HOME/.bash_profile;

# tabtab source for electron-forge package
# uninstall by removing these lines or running `tabtab uninstall electron-forge`
[ -f /Users/david/.nvm/versions/node/v11.5.0/lib/node_modules/electron-forge/node_modules/tabtab/.completions/electron-forge.bash ] && . /Users/david/.nvm/versions/node/v11.5.0/lib/node_modules/electron-forge/node_modules/tabtab/.completions/electron-forge.bash