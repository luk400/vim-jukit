call jukit#util#ipython_info_write('terminal', 'vimterm')

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

fun! s:outhist_job_mode(stay) abort
    if term_getstatus(g:jukit_outhist_title) =~? 'normal'
        exe bufwinnr(g:jukit_outhist_title) . 'wincmd w'
        call feedkeys("i", "nxt")
        if !a:stay
            call feedkeys("\<c-w>:wincmd p\<cr>", "nxt")
        endif
    elseif a:stay
        exe bufwinnr(g:jukit_outhist_title) . 'wincmd w'
    endif
endfun

fun! s:outhist_normal_mode(stay) abort
    if !(term_getstatus(g:jukit_outhist_title) =~? 'normal')
        exe bufwinnr(g:jukit_outhist_title) . 'wincmd w'
        call feedkeys("\<c-w>N", "nxt")
        if !a:stay
            wincmd p
        endif
    elseif a:stay
        exe bufwinnr(g:jukit_outhist_title) . 'wincmd w'
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
    call jukit#util#ipython_info_write('import_complete', 0)
endfun

fun! jukit#vimterm#splits#term() abort
    let g:jukit_output_title = s:setup_term()
    let g:_jukit_python = 0
endfun

fun! jukit#vimterm#splits#history() abort
    let g:jukit_outhist_title = s:setup_term()

    call s:send_keys(g:jukit_outhist_title, jukit#splits#_build_shell_cmd("outhist"), 1)
    call jukit#util#ipython_info_write('import_complete', 0)

    if g:jukit_auto_output_hist
        call jukit#splits#toggle_auto_hist(1)
    endif
endfun

fun! jukit#vimterm#splits#out_hist_scroll(down) abort
    call s:outhist_normal_mode(1)
    if a:down
        call feedkeys("\<c-d>:wincmd p\<cr>", "nxt")
    else
        call feedkeys("\<c-u>:wincmd p\<cr>", "nxt")
    endif
endfun

fun! jukit#vimterm#splits#close_history() abort
    call jukit#splits#toggle_auto_hist(0)

    let g:jukit_outhist_last_cell = -1
    call s:outhist_normal_mode(1)
    quit!
    exe bufwinnr(g:_jukit_main_buf) . 'wincmd w'

    unlet g:jukit_outhist_title
endfun

fun! jukit#vimterm#splits#close_output_split() abort
    exe bufwinnr(g:jukit_output_title) . 'wincmd w'
    quit!
    exe bufwinnr(g:_jukit_main_buf) . 'wincmd w'

    unlet g:jukit_output_title
endfun

fun! jukit#vimterm#splits#show_last_cell_output(force) abort
    call jukit#util#md_buffer_vars()
    if !jukit#vimterm#splits#exists('outhist')
        return
    elseif !exists('g:jukit_outhist_last_cell')
        let g:jukit_outhist_last_cell = -1
    endif

    call jukit#util#ipython_info_write(
        \ ['vimterm_x', 'vimterm_y'],
        \ [winwidth(bufwinnr(g:jukit_outhist_title)), 
        \ winheight(bufwinnr(g:jukit_outhist_title))]
        \ )

    let cell_id = jukit#util#get_current_cell_id()
    
    if cell_id == g:jukit_outhist_last_cell && !a:force
        return
    endif

    call s:outhist_job_mode(0)

    let complete = jukit#util#ipython_info_get(['import_complete', 'output_complete'], 1)
    if type(complete[0]) == 7
        let complete[0] = 1
    elseif type(complete[1]) == 7
        let complete[1] = 1
    endif

    if complete[0] && !complete[1]
        " seems hacky
        call s:send_keys(g:jukit_outhist_title, "", 0)
    endif

    let g:jukit_outhist_last_cell = cell_id

    let save_view = winsaveview()
    call cursor(line('.')+1, '$')
    let md_cur = search(b:jukit_md_start, 'nbW') > search('|%%--%%| <.*|' . cell_id, 'nbW')
    call winrestview(save_view)
    call jukit#util#ipython_info_write(['outhist_cell', 'is_md'], [cell_id, md_cur])
    call s:send_keys(g:jukit_outhist_title, '%jukit_out_hist', 1)
endfun

fun! jukit#vimterm#splits#exists(...) abort
    if !a:0 || a:0 > 0 && a:1 == 'output'
        let output_exists = exists('g:jukit_output_title')
            \ && bufwinnr(g:jukit_output_title) >= 0
    endif

    if !a:0 || a:0 > 0 && a:1 == 'outhist'
        let outhist_exists = exists('g:jukit_outhist_title')
            \ && bufwinnr(g:jukit_outhist_title) >= 0
    endif

    if a:0 > 0 && a:1 == 'output'
        return output_exists
    elseif a:0 > 0 && a:1 == 'outhist'
        return outhist_exists
    else
        return output_exists && outhist_exists
    endif
endfun
