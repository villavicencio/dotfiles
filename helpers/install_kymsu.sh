#!/bin/bash

# Install KYMSU (Keep Your macOS Up-to-date) if not already installed
KYMSU_DIR="$HOME/.config/kymsu"

if [[ ! -d "$KYMSU_DIR" && $(uname 2>/dev/null) == "Darwin" ]]; then
  echo "Installing KYMSU..."

  if git clone "https://github.com/welcoMattic/kymsu" "$KYMSU_DIR"; then
    cd "$KYMSU_DIR" || exit 1
    if ./install.sh; then
      echo "KYMSU installed successfully."
    else
      echo "Error: Failed to run KYMSU install script."
      exit 1
    fi
  else
    echo "Error: Failed to clone KYMSU repository."
    exit 1
  fi
fi
