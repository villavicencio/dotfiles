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

# Set up logging under XDG cache (not the repo root, which the old relative
# path polluted when this ran from the install pipeline).
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
mkdir -p "$LOG_DIR" || handle_error "Unable to create log directory"
LOG_FILE="$LOG_DIR/install_tmux.log"
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
if [ "${DOTFILES_PROFILE:-desk}" = "server" ]; then
  # TPM's install_plugins reads its plugin list and TMUX_PLUGIN_MANAGER_PATH from
  # whatever tmux server is current ($TMUX's, or the default socket's), only
  # starting one, with this repo's config, if none is running. hal may already
  # run tmux for its services, started without this config; TPM then aborts
  # with "Tmux Plugin Manager not configured in tmux.conf" and the install
  # fails. Give TPM a private server in a throwaway socket dir instead, so it
  # always loads this config and never talks to a live server, and stop it
  # afterwards. (Desk installs keep the old behavior.)
  # Under /tmp, not $TMPDIR: macOS caps socket paths at 104 bytes and
  # $TMPDIR (/var/folders/…) plus tmux-UID/default comes close.
  tpm_sock_dir="$(mktemp -d /tmp/dotfiles-tpm.XXXXXX)" && [ -n "$tpm_sock_dir" ] \
    || handle_error "could not create a private tmux socket dir; not running TPM"
  ( unset TMUX; TMUX_TMPDIR="$tpm_sock_dir" "$TPM_INSTALL_DIR/bin/install_plugins" )
  tpm_rc=$?
  ( unset TMUX; TMUX_TMPDIR="$tpm_sock_dir" tmux kill-server >/dev/null 2>&1 )
  rm -rf "$tpm_sock_dir"
  [ "$tpm_rc" -eq 0 ] || handle_error "Failed to install TMux plugins"
else
  "$TPM_INSTALL_DIR/bin/install_plugins" || handle_error "Failed to install TMux plugins"
fi

log_message "TMux installation completed successfully."
