" , Leader key
let mapleader=","
" let localleader=" "
nnoremap <Space> <Nop>

" Map dd to the black hole
nnoremap d "_d
vnoremap d "_d

" Toggle Goyo
nnoremap <Leader>gy :Goyo<CR>


" EASYMOTION {{{

nmap <silent>s <Plug>(easymotion-overwin-f2)

" }}}

" MUNDO {{{

nmap <silent>U :MundoToggle<CR>

" }}}

" PUMPVISIBLE-NAVIGATION {{{

" <TAB>: completion.
inoremap <silent> <expr><TAB> pumvisible() ? "\<C-n>" : "\<TAB>"

" Better nav for omnicomplete
inoremap <expr> <c-j> ("\<C-n>")
inoremap <expr> <c-k> ("\<C-p>")

" }}}

" REPLACE-CURRENT-WORD {{{

nnoremap <F2> :%s/\<<C-r><C-w>\>//gc<Left><Left><Left>

" }}}

" WINDOW {{{

noremap , <PageDown>
noremap ; <PageUp>

nnoremap n nzz
nnoremap N Nzz

" -------------------------------------------------------------Act like D and C
nnoremap Y y$

noremap <C-j> <C-w>j
noremap <C-l> <C-w>l
noremap <C-h> <C-w>h
nnoremap <silent> L :call MyNext()<CR>
nnoremap <silent> H :call MyPrev()<CR>

" ------When I forgot to start vim using sudo
"cnoremap <C-s>w execute 'silent! write !SUDO_ASKPASS=`which ssh-askpass` sudo tee % >/dev/null' <bar> edit!
imap jk <Esc>

" ----------------------------------------------------Firs char in current line
map 0 ^

" ---------------------------------------------------------Move lines (UP/DoWN)
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==
inoremap <A-j> <Esc>:m .+1<CR>==gi
inoremap <A-k> <Esc>:m .-2<CR>==gi
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv

"nnoremap <Leader>o ^o " -Jump back to the position you were last (Out),jump back
"nnoremap <Leader>i ^i " ---Jump back to the position you were last (In), forward

" -------------------------------------------------------Clear search highlight
nnoremap <silent> <F3> :<C-u>nohlsearch<CR>

" -------------------------Vmap for maintain Visual Mode after shifting > and <
vmap < <gv

" -------------------------Vmap for maintain Visual Mode after shifting > and <
vmap > >gv

" ---------------------------SwapSplitResizeShortcuts(): Resizing split windows
if !exists( 'g:resizeshortcuts' )
    let g:resizeshortcuts = 'horizontal'
    nnoremap _ <C-w>-
    nnoremap + <C-w>+
endif

function! SwapSplitResizeShortcuts()
    if g:resizeshortcuts == 'horizontal'
        let g:resizeshortcuts = 'vertical'
        nnoremap _ <C-w><
        nnoremap + <C-w>>
        echo "Vertical split-resizing shortcut mode."
    else
        let g:resizeshortcuts = 'horizontal'
        nnoremap _ <C-w>-
        nnoremap + <C-w>+
        echo "Horizontal split-resizing shortcut mode."
    endif
endfunction

highlight BadWhitespace ctermbg=red guibg=default

" }}}

" RIPGREP {{{

if executable('rg')
    "" Set default grep to ripgrep
    set grepprg=rg\ --vimgrep

    "" Set default ripgrep configs for fzf
    "# --files: List files that would be searched but do not search
    "# --no-ignore: Do not respect .gitignore, etc...
    "# --hidden: Search hidden files and folders
    "# --follow: Follow symlinks
    "# --glob: Additional conditions for search (in this case ignore everything in the .git/ folder)
    let $FZF_DEFAULT_COMMAND ='rg --files --no-ignore --hidden --follow --glob "!.git/*"'

    "" Define custom :Find command to leverage rg
    " --column: Show column number
    " --line-number: Show line number
    " --no-heading: Do not show file headings in results
    " --fixed-strings: Search term as a literal string
    " --ignore-case: Case insensitive search
    " --no-ignore: Do not respect .gitignore, etc...
    " --hidden: Search hidden files and folders
    " --follow: Follow symlinks
    " --glob: Additional conditions for search (in this case ignore everything in the .git/ folder)
    " --color: Search color options
    command! -bang -nargs=* Find call fzf#vim#grep('rg --column --line-number --no-heading --fixed-strings --ignore-case --no-ignore --hidden --follow --glob "!.git/*" --color "always" '.shellescape(<q-args>), 1, <bang>0)
endif

" }}}

" DELETE TRAILING {{{

autocmd BufWrite *.* :call DeleteTrailingWS()

" }}}
