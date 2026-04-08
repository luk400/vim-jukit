fun! s:output_normal_mode(stay) abort
    exe bufwinnr(g:jukit_output_buf) . 'wincmd w'
    call feedkeys("\<c-\>\<c-N>", "nxt")
endfun

fun! s:chan_send(chan, keys, add_enter) abort
    if g:_jukit_is_windows
        call chansend(a:chan, a:keys)
        if a:add_enter
            exec "sleep " . g:_jukit_send_delay
            call chansend(a:chan, "\r")
        endif
    elseif a:add_enter
        call chansend(a:chan, a:keys . "\r")
    else
        call chansend(a:chan, a:keys)
    endif
endfun

fun! s:setup_term() abort
    let g:_jukit_main_buf = bufnr('%', 1)
    split | term
    let job = b:terminal_job_id
    let job_buf = map(getbufinfo(), 'v:val.bufnr')[-1]
    wincmd p
    return [job, job_buf]
endfun

fun! jukit#nvimterm#splits#output(...) abort
    let ids = s:setup_term()
    let g:jukit_output_title = ids[0]
    let g:jukit_output_buf = ids[1]

    if a:0 > 0
        call s:chan_send(g:jukit_output_title, a:1, 1)
    endif

    call s:chan_send(g:jukit_output_title, jukit#splits#_build_shell_cmd(), 1)
    call jukit#util#ipython_info_write({'terminal': 'nvimterm', 'import_complete': 0})
endfun

fun! jukit#nvimterm#splits#term() abort
    let ids = s:setup_term()
    let g:jukit_output_title = ids[0]
    let g:jukit_output_buf = ids[1]

    let g:_jukit_python = 0
endfun

" Page-scroll the output nvim terminal buffer. Bound to <leader>j /
" <leader>k. Originally these scrolled the (deleted) outhist terminal;
" the function name is kept for keybinding-call-site stability.
fun! jukit#nvimterm#splits#out_hist_scroll(down) abort
    call s:output_normal_mode(1)
    if a:down
        call feedkeys("\<c-d>:wincmd p\<cr>", "nxt")
    else
        call feedkeys("\<c-u>:wincmd p\<cr>", "nxt")
    endif
endfun

fun! jukit#nvimterm#splits#close_output_split() abort
    exe 'bdelete! ' . g:jukit_output_buf
    exe bufwinnr(g:_jukit_main_buf) . 'wincmd w'

    unlet g:jukit_output_buf
    unlet g:jukit_output_title
endfun

fun! jukit#nvimterm#splits#exists(...) abort
    let output_exists = exists('g:jukit_output_buf')
        \ && bufwinnr(g:jukit_output_buf) >= 0
    return output_exists
endfun
