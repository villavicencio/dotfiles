" ----------------------------------------------------- Map leader to which_key
nnoremap <silent> <leader> :silent <c-u> :silent WhichKey '<Space>'<CR>
vnoremap <silent> <leader> :silent <c-u> :silent WhichKeyVisual '<Space>'<CR>

let g:which_key_map =  {} " ------------------------- Create map to add keys to
let g:which_key_sep = '→' " -------------------------------- Define a separator
set timeoutlen=100

let g:which_key_use_floating_win = 0 " - Not a fan of floating windows for this

" ----------------------------------------------- Change the colors if you want
highlight default link WhichKey          Operator
highlight default link WhichKeySeperator DiffAdded
highlight default link WhichKeyGroup     Identifier
highlight default link WhichKeyDesc      Function

" ------------------------------------------------------------ Hide status line
autocmd! FileType which_key
autocmd  FileType which_key set laststatus=0 noshowmode noruler
  \| autocmd BufLeave <buffer> set laststatus=2 noshowmode ruler

" ------------------------------------------------------------- Single mappings
let g:which_key_map['/'] = [ ':call Comment()'            , 'comment' ]
let g:which_key_map['0'] = [ ':source $MYVIMRC'           , 'reload init.vim' ]
let g:which_key_map['1'] = [ ':e!'                        , 'reload file' ]
let g:which_key_map['.'] = [ '<Plug>(coc-codeaction)'     , 'coc-codeaction' ]
let g:which_key_map['$'] = [ ':e $MYVIMRC'                , 'open init.vim' ]
let g:which_key_map[';'] = [ ':Commands'                  , 'commands' ]
let g:which_key_map['+'] = [ ':vertical resize +20'       , 'vertical+resize' ]
let g:which_key_map['-'] = [ ':vertical resize -20'       , 'vertical-resize' ]
let g:which_key_map['='] = [ '<C-W>='                     , 'balance windows' ]
let g:which_key_map[']'] = [ '<C-]>'                      , 'go to definition' ]
let g:which_key_map['a'] = [ ':call FoldUnfodlAll()'      , 'unfold-all' ]
let g:which_key_map['p'] = [ ':FloatermNew fzf'           , 'fzf']
let g:which_key_map['?'] = [ 'Buffers'                    , 'fzf-buffer' ]
let g:which_key_map['d'] = [ ':Bdelete'                   , 'delete buffer' ]
let g:which_key_map['D'] = [ ':Bonly'                     , 'delete other buffs' ]
let g:which_key_map['e'] = [ ':CocCommand explorer'       , 'explorer' ]
let g:which_key_map['f'] = [ ':Files'                     , 'search files' ]
let g:which_key_map['g'] = [':FloatermNew lazygit'        , 'lazygit' ]
let g:which_key_map['h'] = [ '<C-W>s'                     , 'split below' ]
let g:which_key_map['i'] = [ ':PlugInstall'               , 'pluginstall' ]
let g:which_key_map['j'] = [ '<Plug>(easymotion-j)'       , 'easymotion-j' ]
let g:which_key_map['k'] = [ '<Plug>(easymotion-k)'       , 'easymotion-k' ]
let g:which_key_map['m'] = [ ':Marks'                     , 'marks' ]
let g:which_key_map['o'] = [ 'zA'                         , 'fold/unfold' ]
let g:which_key_map['r'] = [ ':Rg'                        , 'search text' ]
let g:which_key_map['S'] = [ '<Plug>(easymotion-overwin-f)' , 'easymotion-f' ]
let g:which_key_map['v'] = [ '<C-W>v'                     , 'split right' ]
let g:which_key_map['y'] = [ ':Goyo'                      , 'Goyo' ]
let g:which_key_map['x'] = [ 'daw'                        , 'cut word' ]
let g:which_key_map['z'] = [':FloatermToggle'             , 'zhell' ]

" -------------------------------------------------------------- Group mappings
" a is for actions
let g:which_key_map.A = {
      \ 'name' : '+actions' ,
      \ 'a' : [':Ack!<Space><C-R><C-W>'  , 'Ack! current word'],
      \ 'r' : [':set norelativenumber!'  , 'relative line nums'],
      \ 'p' : ['g;'                      , 'jump back last edit'],
      \ 'n' : ['g,'                      , 'jump next last edit'],
      \ 't' : [':FloatermToggle'         , 'terminal'],
      \ 'V' : [':Vista!!'                , 'tag viewer'],
      \ 'w' : [':w'                      , 'write buffer'],
      \ }

" s is for search
let g:which_key_map.F = {
      \ 'name' : '+search' ,
      \ '/' : [':History/'              , 'history'],
      \ ';' : [':Commands'              , 'commands'],
      \ 'a' : [':Ag'                    , 'text Ag'],
      \ 'b' : [':BLines'                , 'current buffer'],
      \ 'B' : [':Buffers'               , 'open buffers'],
      \ 'c' : [':Commits'               , 'commits'],
      \ 'C' : [':BCommits'              , 'buffer commits'],
      \ 'f' : [':Files'                 , 'files'],
      \ 'g' : [':GFiles'                , 'git files'],
      \ 'G' : [':GFiles?'               , 'modified git files'],
      \ 'h' : [':History'               , 'file history'],
      \ 'H' : [':History:'              , 'command history'],
      \ 'l' : [':Lines'                 , 'lines'] ,
      \ 'm' : [':Marks'                 , 'marks'] ,
      \ 'M' : [':Maps'                  , 'normal maps'] ,
      \ 'p' : [':Helptags'              , 'help tags'] ,
      \ 'P' : [':Tags'                  , 'project tags'],
      \ 's' : [':CocList snippets'      , 'snippets'],
      \ 'S' : [':Colors'                , 'color schemes'],
      \ 't' : [':Rg'                    , 'text Rg'],
      \ 'T' : [':BTags'                 , 'buffer tags'],
      \ 'w' : [':Windows'               , 'search windows'],
      \ 'y' : [':Filetypes'             , 'file types'],
      \ 'z' : [':FZF'                   , 'FZF'],
      \ }

" l is for language server protocol
let g:which_key_map.L = {
      \ 'name' : '+lsp' ,
      \ '.' : [':CocConfig'                          , 'config'],
      \ ';' : ['<Plug>(coc-refactor)'                , 'refactor'],
      \ 'a' : ['<Plug>(coc-codeaction)'              , 'line action'],
      \ 'A' : ['<Plug>(coc-codeaction-selected)'     , 'selected action'],
      \ 'b' : [':CocNext'                            , 'next action'],
      \ 'B' : [':CocPrev'                            , 'prev action'],
      \ 'c' : [':CocList commands'                   , 'commands'],
      \ 'd' : ['<Plug>(coc-definition)'              , 'definition'],
      \ 'D' : ['<Plug>(coc-declaration)'             , 'declaration'],
      \ 'e' : [':CocList extensions'                 , 'extensions'],
      \ 'f' : ['<Plug>(coc-format-selected)'         , 'format selected'],
      \ 'F' : ['<Plug>(coc-format)'                  , 'format'],
      \ 'h' : ['<Plug>(coc-float-hide)'              , 'hide'],
      \ 'i' : ['<Plug>(coc-implementation)'          , 'implementation'],
      \ 'I' : [':CocList diagnostics'                , 'diagnostics'],
      \ 'j' : ['<Plug>(coc-float-jump)'              , 'float jump'],
      \ 'l' : ['<Plug>(coc-codelens-action)'         , 'code lens'],
      \ 'n' : ['<Plug>(coc-diagnostic-next)'         , 'next diagnostic'],
      \ 'N' : ['<Plug>(coc-diagnostic-next-error)'   , 'next error'],
      \ 'o' : ['<Plug>(coc-openlink)'                , 'open link'],
      \ 'O' : [':CocList outline'                    , 'outline'],
      \ 'p' : ['<Plug>(coc-diagnostic-prev)'         , 'prev diagnostic'],
      \ 'P' : ['<Plug>(coc-diagnostic-prev-error)'   , 'prev error'],
      \ 'q' : ['<Plug>(coc-fix-current)'             , 'quickfix'],
      \ 'r' : ['<Plug>(coc-rename)'                  , 'rename'],
      \ 'R' : ['<Plug>(coc-references)'              , 'references'],
      \ 's' : [':CocList -I symbols'                 , 'references'],
      \ 'S' : [':CocList snippets'                   , 'snippets'],
      \ 't' : ['<Plug>(coc-type-definition)'         , 'type definition'],
      \ 'u' : [':CocListResume'                      , 'resume list'],
      \ 'U' : [':CocUpdate'                          , 'update CoC'],
      \ 'v' : [':Vista!!'                            , 'tag viewer'],
      \ 'z' : [':CocDisable'                         , 'disable CoC'],
      \ 'Z' : [':CocEnable'                          , 'enable CoC'],
      \ }

" t is for terminal
let g:which_key_map.T = {
      \ 'name' : '+terminal' ,
      \ ';' : [':FloatermNew --wintype=popup --height=6'        , 'terminal'],
      \ 'f' : [':FloatermNew fzf'                               , 'fzf'],
      \ 'g' : [':FloatermNew lazygit'                           , 'git'],
      \ 'd' : [':FloatermNew lazydocker'                        , 'docker'],
      \ 'n' : [':FloatermNew node'                              , 'node'],
      \ 'N' : [':FloatermNew nnn'                               , 'nnn'],
      \ 'p' : [':FloatermNew python'                            , 'python'],
      \ 'r' : [':FloatermNew ranger'                            , 'ranger'],
      \ 'y' : [':FloatermNew ytop'                              , 'ytop'],
      \ 's' : [':FloatermNew ncdu'                              , 'ncdu'],
      \ }

" Global

autocmd! User vim-which-key call which_key#register('<Space>', 'g:which_key_map')
