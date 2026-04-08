fun! s:send_keys(buffer, keys, add_enter) abort
    if g:_jukit_is_windows
        call term_sendkeys(a:buffer, a:keys)
        if a:add_enter
            exec "sleep " . g:_jukit_send_delay
            call term_sendkeys(a:buffer, "\r")
        endif
    elseif a:add_enter
        call term_sendkeys(a:buffer, a:keys . "\r")
    else
        call term_sendkeys(a:buffer, a:keys)
    endif
endfun

fun! s:output_normal_mode(stay) abort
    if !(term_getstatus(g:jukit_output_title) =~? 'normal')
        exe bufwinnr(g:jukit_output_title) . 'wincmd w'
        call feedkeys("\<c-w>N", "nxt")
        if !a:stay
            wincmd p
        endif
    elseif a:stay
        exe bufwinnr(g:jukit_output_title) . 'wincmd w'
    endif
endfun

fun! s:setup_term() abort
    set termwinsize=0*10
    let g:_jukit_main_buf = bufnr('%', 1)
    term
    wincmd p
    return map(getbufinfo(), 'v:val.bufnr')[-1]
endfun

fun! jukit#vimterm#splits#output(...) abort
    let g:jukit_output_title = s:setup_term()

    if a:0 > 0
        call s:send_keys(g:jukit_output_title, a:1, 1)
    endif

    call s:send_keys(g:jukit_output_title, jukit#splits#_build_shell_cmd(), 1)
    call jukit#util#ipython_info_write({'terminal': 'vimterm', 'import_complete': 0})
endfun

fun! jukit#vimterm#splits#term() abort
    let g:jukit_output_title = s:setup_term()
    let g:_jukit_python = 0
endfun

" Page-scroll the output vim terminal buffer. Bound to <leader>j /
" <leader>k. Originally these scrolled the (deleted) outhist terminal;
" the function name is kept for keybinding-call-site stability.
fun! jukit#vimterm#splits#out_hist_scroll(down) abort
    call s:output_normal_mode(1)
    if a:down
        call feedkeys("\<c-d>:wincmd p\<cr>", "nxt")
    else
        call feedkeys("\<c-u>:wincmd p\<cr>", "nxt")
    endif
endfun

fun! jukit#vimterm#splits#close_output_split() abort
    exe bufwinnr(g:jukit_output_title) . 'wincmd w'
    quit!
    exe bufwinnr(g:_jukit_main_buf) . 'wincmd w'

    unlet g:jukit_output_title
endfun

fun! jukit#vimterm#splits#exists(...) abort
    let output_exists = exists('g:jukit_output_title')
        \ && bufwinnr(g:jukit_output_title) >= 0
    return output_exists
endfun
