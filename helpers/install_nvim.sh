#!/bin/bash

. helpers/env.sh

if test ! -d ~/.config/nvim
then
  git clone "https://github.com/NvChad/NvChad" ~/.config/nvim
fi

nvim --headless -c "autocmd User PackerComplete quitall" -c "PackerSync"
