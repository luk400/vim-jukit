call jukit#util#ipython_info_write('terminal', 'nvimterm')

fun! s:outhist_normal_mode(stay) abort
    exe bufwinnr(g:jukit_outhist_buf) . 'wincmd w'
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
    call jukit#util#ipython_info_write('import_complete', 0)
endfun

fun! jukit#nvimterm#splits#term() abort
    let ids = s:setup_term()
    let g:jukit_output_title = ids[0]
    let g:jukit_output_buf = ids[1]

    let g:_jukit_python = 0
endfun

fun! jukit#nvimterm#splits#history() abort
    let ids = s:setup_term()
    let g:jukit_outhist_title = ids[0]
    let g:jukit_outhist_buf = ids[1]

    call s:chan_send(g:jukit_outhist_title, jukit#splits#_build_shell_cmd("outhist"), 1)
    call jukit#util#ipython_info_write('import_complete', 0)

    if g:jukit_auto_output_hist
        call jukit#splits#toggle_auto_hist(1)
    endif
endfun

fun! jukit#nvimterm#splits#out_hist_scroll(down) abort
    call s:outhist_normal_mode(1)
    if a:down
        call feedkeys("\<c-d>:wincmd p\<cr>", "nxt")
    else
        call feedkeys("\<c-u>:wincmd p\<cr>", "nxt")
    endif
endfun

fun! jukit#nvimterm#splits#close_history() abort
    call jukit#splits#toggle_auto_hist(0)
    let g:jukit_outhist_last_cell = -1

    exe 'bdelete! ' . g:jukit_outhist_buf
    exe bufwinnr(g:_jukit_main_buf) . 'wincmd w'

    unlet g:jukit_outhist_buf
    unlet g:jukit_outhist_title
endfun

fun! jukit#nvimterm#splits#close_output_split() abort
    exe 'bdelete! ' . g:jukit_output_buf
    exe bufwinnr(g:_jukit_main_buf) . 'wincmd w'

    unlet g:jukit_output_buf
    unlet g:jukit_output_title
endfun

fun! jukit#nvimterm#splits#show_last_cell_output(force) abort
    call jukit#util#md_buffer_vars()
    if !jukit#nvimterm#splits#exists('outhist')
        return
    elseif !exists('g:jukit_outhist_last_cell')
        let g:jukit_outhist_last_cell = -1
    endif

    let cell_id = jukit#util#get_current_cell_id()
    
    if cell_id == g:jukit_outhist_last_cell && !a:force
        return
    endif

    let complete = jukit#util#ipython_info_get(['import_complete', 'output_complete'], 1)
    if type(complete[0]) == 7
        let complete[0] = 1
    elseif type(complete[1]) == 7
        let complete[1] = 1
    endif

    if complete[0] && !complete[1]
        " seems hacky
        call s:chan_send(g:jukit_outhist_title, "", 0)
    endif

    let g:jukit_outhist_last_cell = cell_id

    let save_view = winsaveview()
    call cursor(line('.')+1, '$')
    let md_cur = search(b:jukit_md_start, 'nbW') > search('|%%--%%| <.*|' . cell_id, 'nbW')
    call winrestview(save_view)
    call jukit#util#ipython_info_write(['outhist_cell', 'is_md'], [cell_id, md_cur])
    call s:chan_send(g:jukit_outhist_title, '%jukit_out_hist', 1)
    exe bufwinnr(g:jukit_outhist_buf) . 'wincmd w'
    call feedkeys("G:wincmd p\<cr>", "nxt")
endfun

fun! jukit#nvimterm#splits#exists(...) abort
    if !a:0 || a:0 > 0 && a:1 == 'output'
        let output_exists = exists('g:jukit_output_buf')
            \ && bufwinnr(g:jukit_output_buf) >= 0
    endif

    if !a:0 || a:0 > 0 && a:1 == 'outhist'
        let outhist_exists = exists('g:jukit_outhist_buf')
            \ && bufwinnr(g:jukit_outhist_buf) >= 0
    endif

    if a:0 > 0 && a:1 == 'output'
        return output_exists
    elseif a:0 > 0 && a:1 == 'outhist'
        return outhist_exists
    else
        return output_exists && outhist_exists
    endif
endfun
