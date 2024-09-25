#!/usr/bin/env bash

. ./zsh/zshenv

if [ ! -d "$HOME/.config/nvm" ]; then
  echo "Installing NVM..."
  export NVM_DIR="$XDG_CONFIG_HOME/nvm" && (
    git clone https://github.com/nvm-sh/nvm.git "$NVM_DIR" || {
      echo "Failed to clone NVM"
      exit 1
    }
    cd "$NVM_DIR" || {
      echo "Failed to change directory"
      exit 1
    }
    git checkout $(git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1))
  ) && \. "$NVM_DIR/nvm.sh"
  . "$NVM_DIR/nvm.sh"
  echo "NVM installed successfully"
else
  echo "NVM is already installed. Updating to the latest version..."
  cd "$NVM_DIR" && git fetch --tags origin &&
    git checkout $(git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1))
  . "$NVM_DIR/nvm.sh"
fi
