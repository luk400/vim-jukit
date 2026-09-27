fun! jukit#graphics#kitty_upload(path, image_id, cols, rows) abort
    if !has('nvim-0.12')
        throw '[vim-jukit] Kitty-protocol graphics requires Neovim >= 0.12'
    endif
    return luaeval("require('jukit.kitty_graphics').upload(_A[1], _A[2], _A[3], _A[4])", [a:path, a:image_id, a:cols, a:rows])
endfun
