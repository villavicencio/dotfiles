#!/usr/bin/env bash

if ! command -v git &>/dev/null; then
  echo "git is not installed. Please install git and try again." >&2
  exit 1
fi

NVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"

if test ! -d ~/.config/nvim; then
  if ! git clone "https://github.com/NvChad/NvChad" ~/.config/nvim; then
    echo "Failed to clone NvChad repository" >&2
    exit 1
  fi
fi

# Install Packer if not present
if [ ! -d "$NVIM_DATA_DIR/site/pack/packer/start/packer.nvim" ]; then
  if ! git clone --depth 1 https://github.com/wbthomason/packer.nvim \
    "$NVIM_DATA_DIR/site/pack/packer/start/packer.nvim"; then
    echo "Failed to clone Packer repository" >&2
    exit 1
  fi
fi

# Run PackerSync using Lua
#nvim --headless -c "lua require('packer').sync()" -c "autocmd User PackerComplete quitall"
