call jukit#util#ipython_info_write('terminal', 'tmux')

fun! s:wait_for_pane(pane, num_tries, delay)
    let num_tries = a:num_tries
    while !jukit#tmux#cmd#pane_exists(a:pane) && num_tries > 0
        let num_tries -= 1
        redraw!
        echo '[vim-jukit] Waiting for tmux pane...'
        exe 'sleep ' . a:delay . 'm'
    endwhile
    return jukit#tmux#cmd#pane_exists(a:pane)
endfun

fun! jukit#tmux#splits#output(...) abort
    let launch_args = []
    let response = call('jukit#tmux#cmd#launch', launch_args)
    let g:jukit_output_title = matchstr(response, '%\d\{1,}\ze')
    call jukit#tmux#cmd#tmux_command('last-pane')
    call s:wait_for_pane(g:jukit_output_title, 4, 250)

    if a:0 > 0
        call jukit#tmux#cmd#send_text(g:jukit_output_title, a:1)
    endif

    if !g:jukit_inline_plotting && !g:jukit_save_output
        call jukit#tmux#cmd#send_text(g:jukit_output_title, g:jukit_shell_cmd)
        return
    endif

    call jukit#tmux#cmd#send_text(g:jukit_output_title, jukit#splits#_build_shell_cmd())
    call jukit#util#ipython_info_write('import_complete', 0)
endfun

fun! jukit#tmux#splits#term(...) abort
    " Opens a new kitty terminal window

    let g:_jukit_python = 0
    let launch_args = []
    let response = call('jukit#tmux#cmd#launch', launch_args)
    let g:jukit_output_title = matchstr(response, '%\d\{1,}\ze')

    call jukit#tmux#cmd#tmux_command('last-pane')
    call s:wait_for_pane(g:jukit_output_title, 4, 250)
endfun

fun! jukit#tmux#splits#history() abort
    if g:jukit_auto_output_hist
        call jukit#splits#toggle_auto_hist(1)
    endif

    let launch_args = []
    let response = call('jukit#tmux#cmd#launch', launch_args)
    let g:jukit_outhist_title = matchstr(response, '%\d\{1,}\ze')
    call jukit#tmux#cmd#tmux_command('last-pane')

    if exists('g:jukit_output_title')
        call s:wait_for_pane(g:jukit_output_title, 4, 250)
    endif

    call jukit#tmux#cmd#send_text(g:jukit_outhist_title, jukit#splits#_build_shell_cmd('outhist'))
    call jukit#util#ipython_info_write('import_complete', 0)

    " TODO: the following shouldn't be necessary. But otherwise if output
    " split and history split are started together for some reason proportions
    " are not right. Setting the layout again fixes it.
    call jukit#tmux#layouts#set_layout(g:jukit_layout)
endfun

fun! jukit#tmux#splits#out_hist_scroll(down) abort
    call jukit#tmux#cmd#tmux_command('copy-mode', '-t', g:jukit_outhist_title)
    if a:down
        call jukit#tmux#cmd#tmux_command('send-keys', '-t', g:jukit_outhist_title, 'PageDown')
    else
        call jukit#tmux#cmd#tmux_command('send-keys', '-t', g:jukit_outhist_title, 'PageUp')
    endif
endfun

fun! jukit#tmux#splits#close_history() abort
    call jukit#splits#toggle_auto_hist(0)

    let g:jukit_outhist_last_cell = -1
    call jukit#tmux#cmd#tmux_command('kill-pane', '-t', g:jukit_outhist_title)
endfun

fun! jukit#tmux#splits#close_output_split() abort
    call jukit#tmux#cmd#tmux_command('kill-pane', '-t', g:jukit_output_title)
endfun

fun! jukit#tmux#splits#show_last_cell_output(force) abort
    call jukit#util#md_buffer_vars()
    if !jukit#tmux#splits#exists('outhist')
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
        call jukit#tmux#cmd#send_text(g:jukit_outhist_title, '')
    endif

    let g:jukit_outhist_last_cell = cell_id

    let save_view = winsaveview()
    call cursor(line('.')+1, '$')
    let md_cur = search(b:jukit_md_start, 'nbW') > search('|%%--%%| <.*|' . cell_id, 'nbW')
    call winrestview(save_view)
    call jukit#util#ipython_info_write(['outhist_cell', 'outhist_title', 'is_md'],
        \ [cell_id, g:jukit_outhist_title, md_cur])

    " first quit copy mode if active
    call jukit#tmux#cmd#tmux_command('copy-mode', '-t', g:jukit_outhist_title, '-q')
    call jukit#tmux#cmd#send_text(g:jukit_outhist_title, '%jukit_out_hist')
endfun

fun! jukit#tmux#splits#exists(...) abort
    let output_var_exists = exists('g:jukit_output_title')
    let outhist_var_exists = exists('g:jukit_outhist_title')

    if a:0 > 0 && a:1 == 'output' && output_var_exists
        let cmd_output = 'tmux has-session -t ' . g:jukit_output_title
        return !(system(cmd_output)=~"can't find pane")
    elseif a:0 > 0 && a:1 == 'outhist' && outhist_var_exists
        let cmd_outhist = 'tmux has-session -t ' . g:jukit_outhist_title
        return !(system(cmd_outhist)=~"can't find pane")
    elseif output_var_exists && outhist_var_exists
        let cmd_output = 'tmux has-session -t ' . g:jukit_output_title
        let cmd_outhist = 'tmux has-session -t ' . g:jukit_outhist_title
        let both_exist = !(system(cmd_output)=~"can't find pane")
            \ && !(system(cmd_outhist)=~"can't find pane")
        return both_exist
    endif
    return 0
endfun
