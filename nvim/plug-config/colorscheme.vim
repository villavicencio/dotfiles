" DEFAULT-COLORSCHEME {{{

set termguicolors
let g:tokyonight_style = 'night' " -------------------- available: night, storm
let g:tokyonight_enable_italic = 1
colorscheme tokyonight

" }}}

" {{{ Generate random integer to choose color scheme

function! RandInt(Low, High) abort
python3 << EOF
import vim
import random
idx = random.randint(int(vim.eval('a:Low')), int(vim.eval('a:High')))
vim.command("let index = {}".format(idx))
EOF
return index
endfunction

function! RandInt2(Low, High) abort
python << EOF
import vim
import random
idx = random.randint(int(vim.eval('a:Low')), int(vim.eval('a:High')))
vim.command("let index = {}".format(idx))
EOF
return index
endfunction

" }}}

" {{{ Function called anytime the colorscheme is to be changed randomly

function! Init(Max) abort
  let s:p3 = 0
  if has('python3')
    let s:idx = RandInt(0, a:Max)
    let s:p3 = 1
  endif

  if has('python') && !s:p3
    let s:idx = RandInt2(0, a:Max)
  endif

  execute ":call SwitchColor(" . s:idx . ")"
endfunction

" }}}

" SWITCH COLORSCHEME {{{
let loaded_switchcolor = 1

let s:colorschemes = [ 'tokyonight-night', 'nord', 'tokyonight-storm',
      \ 'onedark', 'aranda', 'one', 'iceberg' ]
let s:swback = 0 " -------- background variants light/dark was not yet switched
let s:swindex = 0

function! SwitchColor(swinc)
  " if have switched background: dark/light
  if (s:swback == 1)
    let s:swback = 0
    let s:swindex += a:swinc
    let i = s:swindex % len(s:colorschemes)
    let s:colorscheme = split(s:colorschemes[i], "-")
    if (s:colorschemes[i] == 'tokyonight-night')
      let g:tokyonight_style = 'night' " ------------------------- night, storm
      let g:tokyonight_enable_italic = 1
      let g:tokyonight_transparent_background = 0
      let g:airline_theme='tokyonight' " --------------- Set status bar's theme
      execute "colorscheme " . s:colorscheme[0]
    elseif (s:colorschemes[i] == 'tokyonight-storm')
      let g:tokyonight_style = 'storm' " ------------------------- night, storm
      let g:tokyonight_enable_italic = 1
      let g:tokyonight_transparent_background = 0
      let g:airline_theme='tokyonight' " --------------- Set status bar's theme
      execute "colorscheme " . s:colorscheme[0]
    elseif (s:colorschemes[i] == 'nord')
      set termguicolors
      let g:airline_theme='nord' " --------------------- Set status bar's theme
      execute "colorscheme " . s:colorscheme[0]
    elseif (s:colorschemes[i] == 'onedark')
      let g:airline_theme='onedark'
      execute "colorscheme " . s:colorschemes[i]
    elseif (s:colorschemes[i] == 'aranda')
      let g:airline_theme='aranda'
      execute "colorscheme " . s:colorschemes[i]
    elseif (s:colorschemes[i] == 'one')
      let g:one_allow_italics = 1 " ------------------ For italic for comments
      set background=dark
      let g:airline_theme='one'
      execute "colorscheme " . s:colorschemes[i]
    elseif (s:colorschemes[i] == 'iceberg')
      set background=dark
      let g:airline_theme='iceberg'
      execute "colorscheme " . s:colorschemes[i]
    elseif (s:colorschemes[i] == 'palenight')
      set background=dark
      let g:palenight_terminal_italics=1
      let g:airline_theme='palenight'
      execute "colorscheme " . s:colorschemes[i]
    else
      echo s:colorschemes[i]
      execute "colorscheme " . s:colorschemes[i]
    endif
  else
    let s:swback = 1
    if (&background == "light")
      execute "set background=dark"
    else
      execute "set background=light"
    endif
    " roll back if background is not supported
    if (!exists('g:colors_name'))
      return SwitchColor(a:swinc)
    endif
  endif

  " show current name on screen. :h :echo-redraw
  redraw
  execute "colorscheme"
endfunction

" }}}

" {{{ change color randomly on command

function! ChangeRandomColorscheme() abort
  let g:indicies = Init(len(s:colorschemes))
endfunction

" }}}

" MAPPINGS {{{

map <silent><F8> :call ChangeRandomColorscheme()<CR>
map <silent><F9> :colorscheme aranda<CR>

" }}}
"
" autocmd VimEnter * execute ChangeRandomColorscheme()
