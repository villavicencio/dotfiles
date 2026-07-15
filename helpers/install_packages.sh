#!/usr/bin/env bash

# Cross-platform package installer
# macOS: uses Homebrew + Brewfile
# Linux: uses apt + curated equivalents

if [ "$(uname)" = "Darwin" ]; then
    echo "macOS detected — using Homebrew"
    bash helpers/install_brew.sh
    # Clear legacy-font collisions and install the font casks as one recoverable
    # step BEFORE the main brew bundle — otherwise bundle can't adopt the casks on
    # already-provisioned Macs. Runs here (not as a dotbot pre-step) because it
    # needs brew, which install_brew.sh just bootstrapped. Terminal on failure:
    # if migration rolled back, do NOT proceed to brew bundle (which would hit the
    # same unresolved collision and mask the failure).
    bash helpers/migrate_legacy_fonts.sh || exit $?
    bash helpers/install_from_brewfile.sh
else
    echo "Linux detected — using apt"

    if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
      echo "[dry-run] would apt-get update + install curated package list + gh/starship/diff-so-fancy + fd/bat symlinks"
      exit 0
    fi

    sudo apt-get update -qq

    # Core CLI tools (apt equivalents of Brewfile)
    sudo apt-get install -y \
        bat btop curl fd-find fzf gawk git jq \
        ncdu neovim ripgrep shellcheck tig tmux \
        tree watch wget zsh build-essential cmake \
        luarocks python3-pip pipx

    # GitHub CLI
    if ! command -v gh &>/dev/null; then
        echo "Installing GitHub CLI..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update -qq && sudo apt-get install -y gh
    fi

    # Starship prompt
    if ! command -v starship &>/dev/null; then
        echo "Installing Starship..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi

    # diff-so-fancy (via npm)
    if command -v npm &>/dev/null && ! command -v diff-so-fancy &>/dev/null; then
        echo "Installing diff-so-fancy..."
        npm install -g diff-so-fancy 2>/dev/null || true
    fi

    # Fix Debian/Ubuntu naming quirks
    # fd is packaged as fdfind
    if [ -f /usr/bin/fdfind ] && [ ! -f /usr/local/bin/fd ]; then
        sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
    fi
    # bat is packaged as batcat
    if [ -f /usr/bin/batcat ] && [ ! -f /usr/local/bin/bat ]; then
        sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
    fi

    echo "Linux packages installed successfully."
fi
