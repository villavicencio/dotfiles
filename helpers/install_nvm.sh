#!/bin/bash

. helpers/env.sh

if test ! -d ~/.config/nvm
then
  export NVM_DIR="$XDG_CONFIG_HOME/nvm" && (
  git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR"
  cd "$NVM_DIR"
  git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1)`
) && \. "$NVM_DIR/nvm.sh"
fi
