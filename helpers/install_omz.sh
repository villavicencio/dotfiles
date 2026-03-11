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

# Install plugins
declare -A PLUGINS=(
  ["zsh-256color"]="https://github.com/chrissicool/zsh-256color"
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
  ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
)

for plugin in "${!PLUGINS[@]}"; do
  PLUGIN_DIR="$OMZ_DIR/custom/plugins/$plugin"
  if [[ ! -d "$PLUGIN_DIR" ]]; then
    echo "Installing $plugin..."
    git clone "${PLUGINS[$plugin]}" "$PLUGIN_DIR" || {
      echo "$plugin installation failed"
      exit 1
    }
  else
    echo "$plugin already installed, skipping."
  fi
done

echo "All installations completed successfully."
