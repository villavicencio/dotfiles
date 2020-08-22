" FZF.VIM {{{

" Custom ag command to ignore files in node_modules, .git and include hidden files
command! -bang -nargs=? -complete=dir Files
  \ call fzf#vim#files(<q-args>, {'source': 'ag --hidden --ignore .git -g ""'}, <bang>0)

" ---------------------------------------------------- Just ignore .git folders
command! -bang -nargs=? -complete=dir DefaultFiles
  \ call fzf#vim#files(<q-args>, {'source': 'ag --hidden --skip-vcs-ignores --ignore .git -g ""'}, <bang>0)

" ---------------------- Remapping alt-a, alt-d to ctrl-a, ctrl-d to use on oxs
autocmd VimEnter *
\ command! -bang -nargs=* Ag
\ call fzf#vim#ag(<q-args>, '', { 'options': '--bind ctrl-a:select-all,ctrl-d:deselect-all' }, <bang>0)

" ------------------------------------------------------------- Action mappings
let g:fzf_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

" -------------------- In Neovim, you can set up fzf window using a Vim command
let g:fzf_layout = { 'window': '-tabnew' }

" ----------------------- [[B]Commits] Customize the options used by 'git log':
let g:fzf_commits_log_options = '--color --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'

" ----------------------------------------------- Hide statusline when open fzf
autocmd! FileType fzf
autocmd  FileType fzf set laststatus=0 noshowmode noruler
  \| autocmd BufLeave <buffer> set laststatus=2 showmode ruler

" }}}

" EASY MOTION {{{

let g:EasyMotion_do_mapping = 0 " -------------------- Disable default mappings
let g:EasyMotion_smartcase = 1 " ------------- Turn on case insensitive feature

" }}}

" TREE PAIRS {{{

let g:pear_tree_pairs = {
  \ '(':    {'closer': ')'},
  \ '[':    {'closer': ']'},
  \ '{':    {'closer': '}'},
  \ "'":    {'closer': "'"},
  \ '"':    {'closer': '"'},
  \ '/*':   {'closer': '*/'},
  \ '<!--': {'closer': '-->'}
  \ }

let g:pear_tree_repeatable_expand = 0

" }}}

" PRETTIER {{{

let g:prettier#autoformat = 0
let g:prettier#exec_cmd_async = 1
let g:prettier#config#single_quote = 'true'
let g:prettier#config#bracket_spacing = 'false'

" }}}

" VIM-COMMENTARY {{{

" ------------------------------------ If my favorite file type isn't supported
" autocmd FileType apache setlocal commentstring=#\ %s
autocmd FileType json setlocal commentstring=//\ %s

" }}}

" VIM-ILLUMINATE {{{

hi link illuminatedWord Visual

" }}}
