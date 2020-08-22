" Turn spellcheck on {{{

augroup auto_spellcheck
  autocmd BufNewFile,BufRead *.md setlocal spell
augroup END

" }}}

" CONCEAL/UNCONCEAL {{{

let s:conceal = 0
function! ConcealUnconceal()
  echo "hehehehhe"
  if (s:conceal == 1)
    execute ":set conceallevel=2"
    let s:conceal = 0
  else
    execute ":set conceallevel=0"
    let s:conceal = 1
  endif
endfunction

" }}}

" FOLD/UNFOLD ALL {{{

let s:unfold_all = 0
function! FoldUnfodlAll()
  if (s:unfold_all == 1)
    execute "normal! zM"
    let s:unfold_all = 0
  else
    execute "normal! zR"
    let s:unfold_all = 1
  endif
endfunction

" }}}

"  MyNext() and MyPrev(): Movement between tabs OR buffers {{{

function! MyNext()
    if exists( '*tabpagenr' ) && tabpagenr('$') != 1
        " Tab support && tabs open
        normal gt
    else
        " No tab support, or no tabs open
        execute ":bnext"
    endif
endfunction
function! MyPrev()
    if exists( '*tabpagenr' ) && tabpagenr('$') != '1'
        " Tab support && tabs open
        normal gT
    else
        " No tab support, or no tabs open
        execute ":bprev"
    endif
endfunction

" }}}

" DELETE TRAILING {{{

func! DeleteTrailingWS()
  exe "normal mz"
  %s/\s\+$//ge " /\s\+$/ regex for one or more whitespace characters followed by the end of a line
  exe "normal `z"
endfunc

autocmd BufWrite *.* :call DeleteTrailingWS()

" }}}
