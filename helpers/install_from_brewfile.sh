#!/usr/bin/env bash

# Install packages specified in the Brewfile using Homebrew

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
