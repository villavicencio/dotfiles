#!/usr/bin/env bash

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
