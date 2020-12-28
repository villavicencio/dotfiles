" PYTHON PROVIDERS {{{
"let g:python_version = matchstr(system("python --version | cut -f2 -d' '"), '^[0-9]')
let g:python3_host_prog = '~/.pyenv/shims/python3' " -- Set python 3 provider
let g:python_host_prog = '/usr/bin/python' " --- Set python 2 provider

" }}}


" INTERFACE {{{

:set guioptions-=m " ------------------------------------------ Remove menu bar
:set guioptions-=T " ------------------------------------------- Remove toolbar
:set guioptions-=r " ----------------------------- Remove right-hand scroll bar
:set guioptions-=L " ------------------------------ Remove left-hand scroll bar

set winbl=10 " ----------------- Set floating window to be slightly transparent

" }}}


" DISPLAY {{{

set encoding=utf8
set nowrap " -------------------------------- do not automatically wrap on load
set colorcolumn=80 " -------------------------------------- 80 line column show
set nospell " ------------------------------------------------ Disable spelling
set formatoptions-=t " ------------- Do not automatically wrap text when typing
set listchars=tab:\|\ ,trail:▫
set formatoptions=tcqronj " ------------------ Set vims text formatting options
set title " ------------------------------------ Let vim set the terminal title
set updatetime=300 " ------------------------------ Redraw the status bar often
set timeoutlen=100 " ------------------------- By default timeoutlen is 1000 ms
set list " ------------------------------------------- Show trailing whitespace
set listchars=tab:•\ ,trail:•,extends:»,precedes:« "  Unprintable chars mapping
set showcmd " ------------------------------------- Display incomplete commands
set wildmenu " -------------------------------- Enhance command-line completion
set termencoding=utf-8 " ----------------------------------------- Always utf-8
set fileencoding=utf-8
set hidden " ----------------------------- Buffer becomes hidden when abandoned
set shortmess+=c " ----------------- don't give |ins-completion-menu| messages.
set cmdheight=1 " ------------------------- Just need one line for command line
set laststatus=2 " ------------------------------------ Always show status line
set showtabline=2 " --------------------------------------- Always show tabline
set noshowmode " ------------------------- Hide default mode text (e.g. INSERT)
set display+=lastline " ------------------- As must as possible of the lastline
set signcolumn=yes " -------------------------------- Always open gutter column
set previewheight=3 " ---------------------------------- Smaller preview height
set clipboard=unnamedplus " -------- Copy paste between vim and everything else
set number " ------------------------------------------------- Show line number
set ruler " ---------- Line number, column's number, virtual column's number...
set cursorline " -------------------- Highlight the current line for the cursor
set guifont=Fira\ Code\ Light " ----------------------- Set awesome font to VIM
set nobackup | set nowritebackup " - Some servers have issues with backup files
set ttyfast " -------------------------- Optimize for fast terminal connections
set modeline " ---------------------------------------- File-specific Vim state
set modelines=4 " ----------------------------- Treat first 4 lines as modeline
set nostartofline " ---- Don’t reset cursor to start of line when moving around
set scrolloff=3 " ----- Start scrolling 3 lines before horizontal window border

autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o

" }}}


" SYNTAX {{{

syntax on " -------------------------------------------- Enable Syntax for Code
syntax enable
set foldmethod=manual " -------------------------------- Support fold by indent

" }}}


" COLOR SOLARIZE {{{

set termguicolors " ------------------------------------- True color for neovim

if (empty($TMUX))
  if (has("nvim"))
    let $NVIM_TUI_ENABLE_TRUE_COLOR=1
  endif
  if (has("termguicolors"))
    set termguicolors
  endif
endif

" }}}


" FILE, FILE'S TYPES {{{

filetype on " -------------------------------------- Enable file type detection
set autoread " -------------------------------------- Auto reloaded Edited File
set noswapfile " ---------------------------------------- Dont create swap file
set nobackup " ----------------------------------------------- Dont save backup
filetype plugin on " ------------------------------------------- Turn on plugin
let g:jsx_ext_required = 1 " ----------------------- Dont detect js file as jsx
" ---------------------------------------------------- Treat .json files as .js
autocmd BufNewFile,BufRead *.json setfiletype json syntax=javascript
" ------------------------------------------------- Treat .md files as Markdown
autocmd BufNewFile,BufRead *.md setlocal filetype=markdown

" }}}


" TYPINGS {{{

set backspace=indent,eol,start " --------------- Allow backspace in insert mode

" }}}


" TAB, INDENT {{{

set tabstop=4 " -------------------------------------------- 4 spaces for 1 tab
set softtabstop=4
set shiftwidth=2
set expandtab " ---------------------------------------- Add tab in insert mode
set smarttab
filetype indent on " ----------------------------------- Turn on default indent
set autoindent
set smartindent

" }}}


" SEARCH {{{

set hlsearch " ---------------------------------------- Highlight search result
set incsearch " ---------------------------------------- Allow Insert higtlight
set ignorecase " ----------------------------------- ignore case when searching

" ------------------------ if the search string has an upper case letter in it,
" ------------------------------------------- the search will be case sensitive
set smartcase

" ---------- Automatically re-read file if a change was detected outside of vim
set autoread

set gdefault " -------------------- Add the g flag to search/replace by default

" }}}


" FORMAT {{{

set nrformats-=octal " --------------------------------- Format number as octal

" }}}


" UNDO {{{

set undofile " ------------Enable persistent undo so that undo history persists
set undolevels=100 " ----------------------------- Default is 1000 -> Too large
set undoreload=1000 " --------------------------- Default is 10000 -> Too large
set undodir=~/.tmp/undodir " --------------------- Default folder for undo step

" }}}


" ENABLE MOUSE {{{

if has('mouse')
    set mouse=a " --------------------------- Allow use mouse, possible in nvim
endif

" }}


" Checkboxes
augroup MappyTime
  autocmd!
  autocmd FileType markdown nnoremap <buffer> <silent> - :call winrestview(<SID>toggle('^\s*-\s*\[\zs.\ze\]', {' ': '.', '.': 'x', 'x': ' '}))<cr>
augroup END
function s:toggle(pattern, dict, ...)
  let view = winsaveview()
  execute 'keeppatterns s/' . a:pattern . '/\=get(a:dict, submatch(0), a:0 ? a:1 : " ")/e'
  return view
endfunction


let g:enable_bold_font = 1

" Disable automatic VIM Markdown folding.
let g:vim_markdown_folding_disabled = 1

