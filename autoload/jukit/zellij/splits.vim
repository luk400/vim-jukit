call jukit#util#ipython_info_write({'terminal': 'zellij'})

if !exists('g:jukit_zellij_output_direction')
    let g:jukit_zellij_output_direction = 'right'
endif
if !exists('g:jukit_zellij_outhist_direction')
    let g:jukit_zellij_outhist_direction = 'down'
endif

let s:output_exists = 0
let s:outhist_exists = 0

fun! s:wait_for_pane(num_tries, delay)
    let num_tries = a:num_tries
    while num_tries > 0
        let num_tries -= 1
        redraw!
        echo '[vim-jukit] Waiting for Zellij pane...'
        exe 'sleep ' . a:delay . 'm'
    endwhile
    redraw!
    echo ''
    return 1
endfun

fun! jukit#zellij#splits#output(...) abort
    let direction = g:jukit_zellij_output_direction
    
    let result = jukit#zellij#cmd#launch(direction)
    if type(result) == type(v:null)
        echom '[vim-jukit] Failed to create output pane'
        return
    endif
    
    let g:jukit_output_title = 'output'
    let s:output_exists = 1
    
    call s:wait_for_pane(2, 150)
    
    if a:0 > 0
        call jukit#zellij#cmd#send_text('output', a:1)
    endif
    
    if !g:jukit_inline_plotting && !g:jukit_save_output
        call jukit#zellij#cmd#send_text('output', g:jukit_shell_cmd)
        return
    endif
    
    call jukit#zellij#cmd#send_text('output', jukit#splits#_build_shell_cmd())
    call jukit#util#ipython_info_write({'import_complete': 0})
endfun

fun! jukit#zellij#splits#term(...) abort
    let g:_jukit_python = 0
    let direction = g:jukit_zellij_output_direction
    
    let result = jukit#zellij#cmd#launch(direction)
    if type(result) == type(v:null)
        echom '[vim-jukit] Failed to create terminal pane'
        return
    endif
    
    let g:jukit_output_title = 'output'
    let s:output_exists = 1
    
    call s:wait_for_pane(2, 150)
endfun

fun! jukit#zellij#splits#history(...) abort
    if g:jukit_auto_output_hist
        call jukit#splits#toggle_auto_hist(1)
    endif
    
    if s:output_exists
        call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
        sleep 100m
    endif
    
    let direction = g:jukit_zellij_outhist_direction
    let result = jukit#zellij#cmd#launch(direction)
    
    call jukit#zellij#cmd#return_to_vim()
    sleep 100m
    call jukit#zellij#cmd#return_to_vim()
    
    if type(result) == type(v:null)
        echom '[vim-jukit] Failed to create history pane'
        return
    endif
    
    let g:jukit_outhist_title = 'outhist'
    let s:outhist_exists = 1
    
    call s:wait_for_pane(2, 150)
    
    if a:0 > 0
        call jukit#zellij#splits#_send_to_outhist(a:1)
    endif
    
    call jukit#zellij#splits#_send_to_outhist(jukit#splits#_build_shell_cmd('outhist'))
    call jukit#util#ipython_info_write({'import_complete': 0})
    
    if s:output_exists && s:outhist_exists
        call jukit#zellij#layouts#set_layout(g:jukit_layout)
    endif
endfun

fun! jukit#zellij#splits#_send_to_outhist(text) abort
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
    sleep 50m
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_outhist_direction)
    sleep 50m
    
    let text = substitute(a:text, '\n$\|\r$', '', '')
    call jukit#zellij#cmd#zellij_command('write-chars', text)
    call jukit#zellij#cmd#zellij_command('write', '13')
    
    sleep 50m
    call jukit#zellij#cmd#return_to_vim()
    sleep 50m
    call jukit#zellij#cmd#return_to_vim()
endfun

fun! jukit#zellij#splits#out_hist_scroll(down) abort
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
    sleep 50m
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_outhist_direction)
    sleep 50m
    
    if a:down
        call jukit#zellij#cmd#zellij_command('page-scroll-down')
    else
        call jukit#zellij#cmd#zellij_command('page-scroll-up')
    endif
    
    sleep 50m
    call jukit#zellij#cmd#return_to_vim()
    sleep 50m
    call jukit#zellij#cmd#return_to_vim()
endfun

fun! jukit#zellij#splits#close_history() abort
    call jukit#splits#toggle_auto_hist(0)
    let g:jukit_outhist_last_cell = -1
    
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
    sleep 50m
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_outhist_direction)
    sleep 50m
    call jukit#zellij#cmd#zellij_command('close-pane')
    
    sleep 50m
    call jukit#zellij#cmd#return_to_vim()
    
    let s:outhist_exists = 0
    unlet! g:jukit_outhist_title
endfun

fun! jukit#zellij#splits#close_output_split() abort
    if s:outhist_exists
        call jukit#zellij#splits#close_history()
    endif
    
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
    sleep 50m
    call jukit#zellij#cmd#zellij_command('close-pane')
    
    let s:output_exists = 0
    unlet! g:jukit_output_title
endfun

fun! jukit#zellij#splits#show_last_cell_output(force) abort
    call jukit#util#md_buffer_vars()
    
    if !jukit#zellij#splits#exists('outhist')
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
        call jukit#zellij#splits#_send_to_outhist('')
    endif
    
    let g:jukit_outhist_last_cell = cell_id
    
    let md_cur = jukit#util#is_md_cell(cell_id)
    call jukit#util#ipython_info_write({
        \ 'outhist_cell': cell_id, 
        \ 'outhist_title': g:jukit_outhist_title, 
        \ 'is_md': md_cur
        \ })
    
    call jukit#zellij#splits#_send_to_outhist('%jukit_out_hist')
endfun

fun! jukit#zellij#splits#exists(...) abort
    if a:0 > 0 && a:1 ==# 'output'
        return s:output_exists && exists('g:jukit_output_title')
    elseif a:0 > 0 && a:1 ==# 'outhist'
        return s:outhist_exists && exists('g:jukit_outhist_title')
    else
        return s:output_exists && s:outhist_exists
    endif
endfun

fun! jukit#zellij#splits#send_to_output(text) abort
    if !s:output_exists
        echom '[vim-jukit] Output pane does not exist'
        return
    endif
    call jukit#zellij#cmd#send_text('output', a:text)
endfun

fun! jukit#zellij#splits#reset() abort
    let s:output_exists = 0
    let s:outhist_exists = 0
    unlet! g:jukit_output_title
    unlet! g:jukit_outhist_title
    let g:jukit_outhist_last_cell = -1
endfun
