" FOLDING {{{

augroup folding_vim
  autocmd!
  autocmd FileType vim,snippets,lua setlocal foldmethod=marker
  autocmd FileType python setlocal foldmethod=indent
augroup END

augroup XML
    autocmd!
    autocmd FileType xml let g:xml_syntax_folding=1
    autocmd FileType xml setlocal foldmethod=syntax
    autocmd FileType xml :syntax on
    autocmd FileType xml :%foldopen!
augroup END
" }}}
