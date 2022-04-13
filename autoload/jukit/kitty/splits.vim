call jukit#util#ipython_info_write('terminal', 'kitty')

fun! jukit#kitty#splits#output(...) abort
    let g:jukit_output_title=jukit#util#get_unique_id()

    let launch_args = [g:jukit_output_title, '--keep-focus', '--cwd=' . getcwd()]
    if g:jukit_output_bg_color != ''
        let launch_args += ['--color', 'background=' . g:jukit_output_bg_color]
    endif
    if g:jukit_output_fg_color != ''
        let launch_args += ['--color', 'foreground=' . g:jukit_output_fg_color]
    endif
    if g:jukit_output_new_os_window
        let launch_args += ['--type=os-window']
    endif
    call call('jukit#kitty#cmd#launch', launch_args)

    if a:0 > 0
        call jukit#kitty#cmd#send_text(g:jukit_output_title, a:1)
    endif

    if !g:jukit_inline_plotting && !g:jukit_save_output
        call jukit#kitty#cmd#send_text(g:jukit_output_title, g:jukit_shell_cmd)
        return
    endif

    call jukit#kitty#cmd#send_text(g:jukit_output_title, jukit#splits#_build_shell_cmd())
    call jukit#util#ipython_info_write('import_complete', 0)
endfun

fun! jukit#kitty#splits#term(...) abort
    " Opens a new kitty terminal window

    let g:_jukit_python = 0
    let g:jukit_output_title=jukit#util#get_unique_id()
    let launch_args = [g:jukit_output_title, '--keep-focus', '--cwd=' . getcwd()]
    if g:jukit_output_new_os_window
        let launch_args += ['--type=os-window']
    endif
    call call('jukit#kitty#cmd#launch', launch_args)
endfun

fun! jukit#kitty#splits#history() abort
    if g:jukit_auto_output_hist
        call jukit#splits#toggle_auto_hist(1)
    endif

    let g:jukit_outhist_title=jukit#util#get_unique_id()
    let launch_args = [g:jukit_outhist_title, '--keep-focus', '--cwd=' . getcwd()]
    if g:jukit_outhist_bg_color != -1
        let launch_args += ['--color', 'background=' . g:jukit_outhist_bg_color]
    endif
    if g:jukit_outhist_fg_color != -1
        let launch_args += ['--color', 'foreground=' . g:jukit_outhist_fg_color]
    endif
    if g:jukit_outhist_new_os_window
        let launch_args += ['--type=os-window']
    endif
    let response = call('jukit#kitty#cmd#launch', launch_args)

    if type(response) == 7
        call jukit#kitty#cmd#launch(g:jukit_outhist_title, '--keep-focus', '--cwd=' . getcwd())
    endif

    call jukit#kitty#cmd#send_text(g:jukit_outhist_title, jukit#splits#_build_shell_cmd('outhist'))
    call jukit#util#ipython_info_write('import_complete', 0)
endfun

fun! jukit#kitty#splits#out_hist_scroll(down) abort
    if a:down
        call jukit#kitty#cmd#kitty_command('scroll-window', "--match", 
            \ "title:" . g:jukit_outhist_title, '1p')
    else
        call jukit#kitty#cmd#kitty_command('scroll-window', "--match", 
            \ "title:" . g:jukit_outhist_title, '1p-')
    endif
endfun

fun! jukit#kitty#splits#close_history() abort
    call jukit#splits#toggle_auto_hist(0)

    let g:jukit_outhist_last_cell = -1
    call jukit#kitty#cmd#close_window(g:jukit_outhist_title)
endfun

fun! jukit#kitty#splits#close_output_split() abort
    call jukit#kitty#cmd#close_window(g:jukit_output_title)
endfun

fun! jukit#kitty#splits#show_last_cell_output(force) abort
    call jukit#util#md_buffer_vars()
    if !jukit#kitty#splits#exists('outhist')
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
        call jukit#kitty#cmd#send_text(g:jukit_outhist_title, '')
    endif

    let g:jukit_outhist_last_cell = cell_id

    let save_view = winsaveview()
    call cursor(line('.')+1, '$')
    let md_cur = search(b:jukit_md_start, 'nbW') > search('|%%--%%| <.*|' . cell_id, 'nbW')
    call winrestview(save_view)
    call jukit#util#ipython_info_write(['outhist_cell', 'outhist_title', 'is_md'],
        \ [cell_id, g:jukit_outhist_title, md_cur])
    call jukit#kitty#cmd#send_text(g:jukit_outhist_title, '%jukit_out_hist')
endfun

fun! s:search_current_tab() abort
    let kitty_tabs = json_decode(jukit#kitty#cmd#kitty_command('ls'))[0]['tabs']
    let output_exists = 0
    let outhist_exists = 0

    call filter(kitty_tabs, {k,v -> v["is_focused"]})
    if exists('g:jukit_output_title')
        let output_exists = len(filter(copy(kitty_tabs[0]['windows']),
            \ {k,v -> v["title"]=~g:jukit_output_title})) > 0
    endif

    if exists('g:jukit_outhist_title')
        let outhist_exists = len(filter(copy(kitty_tabs[0]['windows']),
            \ {k,v -> v["title"]=~g:jukit_outhist_title})) > 0
    endif

    return {'output': output_exists, 'outhist': outhist_exists}
endfun

fun! s:search_all_windows() abort
    let all_os_windows = json_decode(jukit#kitty#cmd#kitty_command('ls'))
    let output_exists = 0
    let outhist_exists = 0

    "TODO: possible to make one big filter/map function to replace for-loops?
    for os_window in all_os_windows
        for tab_ in os_window['tabs']
            if exists('g:jukit_output_title')
                let output_exists += len(filter(copy(tab_['windows']),
                    \ {k,v -> v["title"]=~g:jukit_output_title})) > 0
            endif

            if exists('g:jukit_outhist_title')
                let outhist_exists += len(filter(copy(tab_['windows']),
                    \ {k,v -> v["title"]=~g:jukit_outhist_title})) > 0
            endif
        endfor
    endfor

    return {'output': output_exists, 'outhist': outhist_exists}
endfun

fun! jukit#kitty#splits#exists(...) abort
    if g:jukit_output_new_os_window || g:jukit_outhist_new_os_window
        let existence = s:search_all_windows()
    else
        let existence = s:search_current_tab()
    endif

    if a:0 > 0 && a:1 == 'output'
        return existence['output']
    elseif a:0 > 0 && a:1 == 'outhist'
        return existence['outhist']
    else
        return existence['output'] && existence['outhist']
    endif
endfun
