" auto-install vim-plug
if empty(glob('~/.config/nvim/autoload/plug.vim'))
  silent !curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall | source $MYVIMRC
endif

call plug#begin('~/.config/nvim/autoload/plugged') " ----------- Start vim plug

Plug 'airblade/vim-gitgutter'
Plug 'airblade/vim-rooter' " --------- Auto changes working dir to project root
Plug 'christoomey/vim-tmux-navigator' " ---- Easier nav between vim tmux splits
Plug 'easymotion/vim-easymotion' " --------- Jump around the screen like a boss
Plug 'elzr/vim-json' " --------------------- JSON front matter highlight plugin
Plug 'ghifarit53/tokyonight-vim'
Plug 'godlygeek/tabular' " ------------ tabular plugin is used to format tables
Plug 'google/vim-codefmt'
Plug 'google/vim-maktaba'
Plug 'google/yapf'
Plug 'iamcco/markdown-preview.nvim', { 'do': { -> mkdp#util#install() }, 'for': ['markdown', 'vim-plug']}
Plug 'junegunn/fzf', { 'do': { -> fzf#install() }}
Plug 'junegunn/fzf.vim' " ------------------------------------------ fzf in vim
Plug 'junegunn/goyo.vim'
Plug 'junegunn/limelight.vim'
Plug 'kevinhwang91/rnvimr', {'do': 'make sync'} " ---------- Ranger integration
Plug 'liuchengxu/vim-which-key', { 'on': ['WhichKey', 'WhichKey!'] }
Plug 'lukas-reineke/indent-blankline.nvim'
Plug 'mg979/vim-visual-multi' " ------------------------------- Multiple Cursor
Plug 'mileszs/ack.vim' " ---------- Don't forget: sudo apt-get install ack-grep
Plug 'moll/vim-bbye' " ------ Allows you to delete current buffer (close files)
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'NLKNguyen/copy-cut-paste.vim' " -------------- Copy, Paste with Clipboard
Plug 'norcalli/nvim-colorizer.lua'
Plug 'ntpeters/vim-better-whitespace' "Highlight trailing whitespace characters
Plug 'plasticboy/vim-markdown'
Plug 'reedes/vim-colors-pencil'
Plug 'reedes/vim-lexical' " ------------------------ Better spellcheck mappings
Plug 'reedes/vim-litecorrect' " ------------------------ Better autocorrections
Plug 'reedes/vim-pencil'
Plug 'reedes/vim-textobj-sentence' " ---------- Treat sentences as text objects
Plug 'reedes/vim-wordy' " ---------------------- Weasel words and passive voice
Plug 'ron89/thesaurus_query.vim'
Plug 'RRethy/vim-illuminate' " - Auto highlight other uses of word under cursor
Plug 'ryanoasis/vim-devicons'
Plug 'segeljakt/vim-silicon' " -------- Generate image of selected source code
Plug 'sheerun/vim-polyglot' " ---------- A collection of language packs for vim
Plug 'simnalamburt/vim-mundo'
Plug 'skbolton/embark'
Plug 'TaDaa/vimade'
Plug 'terryma/vim-expand-region' " --- Expand visual selection by region w/ + -
Plug 'tmsvg/pear-tree' " ----------------------------------- Auto pair brackets
Plug 'tpope/vim-abolish' " -------------------- Fancy abbreviation replacements
Plug 'tpope/vim-commentary' " ------------------------------- Comment stuff out
Plug 'tpope/vim-fugitive' " -------- Just use to show git status in Vim-Airline
Plug 'tpope/vim-repeat' " ----------------------------- dot repeat with plugins
Plug 'tpope/vim-sleuth' " ----------------------------- Auto set indent setting
Plug 'tpope/vim-surround' " ------------------------------------- Auto surround
Plug 'vim-airline/vim-airline' " -------------------------- Status bar, Tabline
Plug 'vim-pandoc/vim-pandoc-syntax'
Plug 'vim-scripts/BufOnly.vim' " --------------- Allows to delete other buffers
Plug 'vitalk/vim-shebang' " ------------ Vim filetype detection by the she·bang

if has('nvim') || has('patch-8.0.902')
  Plug 'mhinz/vim-signify' " - indicate added, modified and removed lines (VCS)
else
  Plug 'mhinz/vim-signify', { 'branch': 'legacy' }
endif

call plug#end() " -------------------------------------- End of Vim-Plug define

" ---------------------------- Automatically install missing plugins on startup
autocmd VimEnter *
  \  if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  \|   PlugInstall --sync | q
  \| endif
