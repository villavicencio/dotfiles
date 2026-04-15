#!/usr/bin/env bash

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install TPM + tmux plugins"
  exit 0
fi

. ./zsh/zshenv

# Source brew only on macOS
if [ "$(uname)" = "Darwin" ] && [ -f ./helpers/init_homebrew.sh ]; then
    . ./helpers/init_homebrew.sh
fi

# Function to log messages
log_message() {
  echo "$1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
  log_message "Error: $1" >&2
  exit 1
}

# Set up logging
LOG_FILE="install_tmux.log"
touch "$LOG_FILE" || handle_error "Unable to create log file"

TPM_INSTALL_DIR="$HOME/.config/tmux/plugins/tpm"
TPM_REPO_URL="https://github.com/tmux-plugins/tpm"

log_message "Starting TMux installation..."

# Install TPM
if [ ! -d "$TPM_INSTALL_DIR" ]; then
  log_message "Installing TPM..."
  git clone "$TPM_REPO_URL" "$TPM_INSTALL_DIR" || handle_error "Failed to clone TPM repository"
else
  log_message "TPM already installed, skipping..."
fi

# Install TMux plugins
log_message "Installing TMux plugins..."
"$TPM_INSTALL_DIR/bin/install_plugins" || handle_error "Failed to install TMux plugins"

log_message "TMux installation completed successfully."
