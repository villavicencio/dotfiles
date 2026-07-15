#!/usr/bin/env bash

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install Homebrew via the official install.sh if it isn't already present"
  exit 0
fi

# This script checks if Homebrew is installed and installs it if not present
if ! command -v brew &>/dev/null; then
    echo "Homebrew not found. Installing..."
    if ! /bin/bash -c "$(curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")" </dev/null; then
        echo "Error: Homebrew installation failed" >&2
        exit 1
    fi
    echo "Homebrew has been successfully installed."
else
    echo "Homebrew is already installed."
fi
