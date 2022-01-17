#!/bin/bash

. helpers/env.sh

if test ! -d ~/.config/tmux/plugins/tpm 
then
  git clone "https://github.com/tmux-plugins/tpm" ~/.config/tmux/plugins/tpm
fi

~/.config/tmux/plugins/tpm/bin/install_plugins
