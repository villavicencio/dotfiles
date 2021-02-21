source $DOTFILES/nvim/vim-plug/plugins.vim
source $DOTFILES/nvim/general/settings.vim
source $DOTFILES/nvim/general/functions.vim
source $DOTFILES/nvim/general/folding.vim
source $DOTFILES/nvim/general/indent.vim
source $DOTFILES/nvim/general/spell.vim
source $DOTFILES/nvim/keys/mappings.vim
source $DOTFILES/nvim/keys/which_key.vim

source $DOTFILES/nvim/themes/airline.vim
source $DOTFILES/nvim/plug-config/plugins.vim
source $DOTFILES/nvim/plug-config/coc.vim
source $DOTFILES/nvim/plug-config/autoformat.vim
source $DOTFILES/nvim/plug-config/floaterm.vim
source $DOTFILES/nvim/plug-config/fzf.vim
source $DOTFILES/nvim/plug-config/sneak.vim
source $DOTFILES/nvim/plug-config/gitgutter.vim
source $DOTFILES/nvim/plug-config/rnvimr.vim
source $DOTFILES/nvim/plug-config/vim-commentary.vim
source $DOTFILES/nvim/plug-config/colorscheme.vim
source $DOTFILES/nvim/plug-config/goyo.vim
source $DOTFILES/nvim/plug-config/pencil.vim
source $DOTFILES/nvim/plug-config/markdown-preview.vim
source $DOTFILES/nvim/plug-config/vimade.vim
source $DOTFILES/nvim/plug-config/indentline.vim
let g:silicon = {
      \   'theme':              'Dracula',
      \   'font':                  'Hack',
      \   'background':         '#FFFFFF',
      \   'shadow-color':       '#555555',
      \   'line-pad':                   2,
      \   'pad-horiz':                 80,
      \   'pad-vert':                 100,
      \   'shadow-blur-radius':         0,
      \   'shadow-offset-x':            0,
      \   'shadow-offset-y':            0,
      \   'line-number':           v:true,
      \   'round-corner':          v:true,
      \   'window-controls':       v:true,
      \ }
luafile $DOTFILES/nvim/lua/plug-colorizer.lua
