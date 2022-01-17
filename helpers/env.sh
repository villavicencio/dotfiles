#!/bin/bash

# Add XDG base directory specification support.
export XDG_CONFIG_HOME=$HOME/.config
export XDG_DATA_HOME=$HOME/.local/share
export XDG_CACHE_HOME=$HOME/.cache

# Save reference to dotfiles directory.
export DOTFILES=$( cd -P "$( dirname "$( readlink $HOME/.zshrc )" )" \
 >/dev/null 2>&1 && git rev-parse --show-toplevel )

# Upate PATH
if test $(uname 2> /dev/null) = "Darwin"
then
  export PATH="/usr/local/bin:$PATH"
else
  export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
fi
