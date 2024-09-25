#!/bin/bash

# Determine the operating system and set the appropriate font directory
if [ "$(uname)" = "Darwin" ]; then
  font_dir="$HOME/Library/Fonts"
else
  font_dir="$HOME/.local/share/fonts"
fi

# Ensure the destination directory exists
mkdir -p "$font_dir"

# Check if the fonts directory exists and is not empty
if [ ! -d "fonts" ] || [ -z "$(ls -A fonts)" ]; then
  echo "Error: fonts directory is missing or empty" >&2
  exit 1
fi

# Copy the fonts
if cp fonts/* "$font_dir/"; then
  echo "Fonts installed successfully to $font_dir"
else
  echo "Error: Failed to copy fonts" >&2
  exit 1
fi
