function! s:goyo_enter()
    "set Guifont=Fira\ Code\ Light:h16
    Limelight 0.33
endfunction

function! s:goyo_leave()
    "set Guifont=Fira\ Code\ Light:h12
    Limelight!
endfunction

" Turn Limelight on/off depending if Goyo is enabled.
autocmd! User GoyoEnter nested call <SID>goyo_enter()
autocmd! User GoyoLeave nested call <SID>goyo_leave()

