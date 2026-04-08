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
    call jukit#util#ipython_info_write({'terminal': 'kitty', 'import_complete': 0})
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

" Page-scroll the output kitty window. Bound to <leader>j / <leader>k.
" Originally these scrolled the (deleted) outhist window; the function
" name is kept for keybinding-call-site stability.
fun! jukit#kitty#splits#out_hist_scroll(down) abort
    if a:down
        call jukit#kitty#cmd#kitty_command('scroll-window', "--match",
            \ "title:" . g:jukit_output_title, '1p')
    else
        call jukit#kitty#cmd#kitty_command('scroll-window', "--match",
            \ "title:" . g:jukit_output_title, '1p-')
    endif
endfun

fun! jukit#kitty#splits#close_output_split() abort
    call jukit#kitty#cmd#close_window(g:jukit_output_title)
endfun

fun! s:search_current_tab() abort
    let kitty_tabs = json_decode(jukit#kitty#cmd#kitty_command('ls'))[0]['tabs']
    let output_exists = 0

    call filter(kitty_tabs, {k,v -> v["is_focused"]})
    if exists('g:jukit_output_title')
        let output_exists = len(filter(copy(kitty_tabs[0]['windows']),
            \ {k,v -> v["title"]=~g:jukit_output_title})) > 0
    endif

    return {'output': output_exists}
endfun

fun! s:search_all_windows() abort
    let all_os_windows = json_decode(jukit#kitty#cmd#kitty_command('ls'))
    let output_exists = 0

    "TODO: possible to make one big filter/map function to replace for-loops?
    for os_window in all_os_windows
        for tab_ in os_window['tabs']
            if exists('g:jukit_output_title')
                let output_exists += len(filter(copy(tab_['windows']),
                    \ {k,v -> v["title"]=~g:jukit_output_title})) > 0
            endif
        endfor
    endfor

    return {'output': output_exists}
endfun

fun! jukit#kitty#splits#exists(...) abort
    if g:jukit_output_new_os_window
        let existence = s:search_all_windows()
    else
        let existence = s:search_current_tab()
    endif

    return existence['output']
endfun
