#!/usr/bin/env sh

# This script sets up the Homebrew environment by finding and initializing the Homebrew installation

setup_homebrew_environment() {
    for brew_path in "/opt/homebrew/bin/brew" "/usr/local/bin/brew" "/home/linuxbrew/.linuxbrew/bin/brew"; do
        if [ -x "$brew_path" ]; then
            eval "$($brew_path shellenv)"
            return 0
        fi
    done
    echo "Error: Homebrew installation not found." >&2
    return 1
}

if ! setup_homebrew_environment; then
    echo "Failed to set up Homebrew environment. Please ensure Homebrew is installed." >&2
    exit 1
fi
