#!/bin/bash

if test ! -d ~/.oh-my-zsh
then
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

if test ! -d ~/.oh-my-zsh/custom/plugins/zsh-256color
then
  git clone "https://github.com/chrissicool/zsh-256color" ~/.oh-my-zsh/custom/plugins/zsh-256color 
fi
