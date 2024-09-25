#!/usr/bin/env bash

. ./zsh/zshenv
. ./helpers/init_homebrew.sh

# Set up logging
LOG_FILE="install_tmux.log"
touch "$LOG_FILE" || handle_error "Unable to create log file"

# Function to log messages
log_message() {
  echo "$1" | tee -a "$LOG_FILE"
}

TPM_INSTALL_DIR="$HOME/.config/tmux/plugins/tpm"
TPM_REPO_URL="https://github.com/tmux-plugins/tpm"

# Error handling function
handle_error() {
  log_message "Error: $1" >&2
  exit 1
}

log_message "Starting TMux installation..."

# Install TPM
if [ ! -d ~/.config/tmux/plugins/tpm ]; then
  log_message "Installing TPM..."
  git clone "$TPM_REPO_URL" "$TPM_INSTALL_DIR" || handle_error "Failed to clone TPM repository"
else
  log_message "TPM already installed, skipping..."
fi

# Install TMux plugins
log_message "Installing TMux plugins..."
~/.config/tmux/plugins/tpm/bin/install_plugins || handle_error "Failed to install TMux plugins"

log_message "TMux installation completed successfully."
