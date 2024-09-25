#!/usr/bin/env bash

# Define the Oh My Zsh installation directory
OMZ_DIR="$HOME/.oh-my-zsh"

# Install Oh My Zsh if not already installed
if [[ ! -d "$OMZ_DIR" ]]; then
  echo "Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || {
    echo "Oh My Zsh installation failed"
    exit 1
  }
fi

# Install zsh-256color plugin if not already installed
ZSH_256COLOR_DIR="$OMZ_DIR/custom/plugins/zsh-256color"
if [[ ! -d "$ZSH_256COLOR_DIR" ]]; then
  echo "Installing zsh-256color plugin..."
  git clone "https://github.com/chrissicool/zsh-256color" "$ZSH_256COLOR_DIR" || {
    echo "zsh-256color plugin installation failed"
    exit 1
  }
fi

echo "All installations completed successfully."
