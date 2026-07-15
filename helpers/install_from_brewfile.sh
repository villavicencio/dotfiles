#!/usr/bin/env bash

# Install packages specified in the Brewfile using Homebrew

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would run: brew bundle --file=${BREWFILE_PATH:-./brew/Brewfile}"
  exit 0
fi

# Source the Homebrew initialization script
. "./helpers/init_homebrew.sh"

# Set the Brewfile path (can be overridden by setting BREWFILE_PATH environment variable)
BREWFILE_PATH=${BREWFILE_PATH:-"./brew/Brewfile"}

# Run brew bundle and handle potential errors
if ! brew bundle --file="$BREWFILE_PATH"; then
    echo "Error: Failed to install packages from Brewfile"
    exit 1
fi

echo "Successfully installed packages from Brewfile"
