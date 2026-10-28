#!/usr/bin/env bash

. ./zsh/zshenv

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install/update NVM at ${NVM_DIR:-$XDG_CONFIG_HOME/nvm} and source nvm.sh"
  exit 0
fi

# Check out nvm's newest release tag in the current directory.
checkout_latest_tag() {
  git checkout "$(git describe --abbrev=0 --tags --match "v[0-9]*" "$(git rev-list --tags --max-count=1)")"
}

if [ ! -d "$NVM_DIR" ]; then
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
    checkout_latest_tag
  ) && \. "$NVM_DIR/nvm.sh"
  echo "NVM installed successfully"
else
  echo "NVM is already installed. Updating to the latest version..."
  cd "$NVM_DIR" && git fetch --tags origin &&
    checkout_latest_tag
  . "$NVM_DIR/nvm.sh"
fi
