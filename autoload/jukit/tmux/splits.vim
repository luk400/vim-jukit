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
    call jukit#util#ipython_info_write({'terminal': 'tmux', 'import_complete': 0})
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

" Page-scroll the output tmux pane. Bound to <leader>j / <leader>k.
" Originally these scrolled the (deleted) outhist pane; the function
" name is kept for keybinding-call-site stability.
fun! jukit#tmux#splits#out_hist_scroll(down) abort
    call jukit#tmux#cmd#tmux_command('copy-mode', '-t', g:jukit_output_title)
    if a:down
        call jukit#tmux#cmd#tmux_command('send-keys', '-t', g:jukit_output_title, 'PageDown')
    else
        call jukit#tmux#cmd#tmux_command('send-keys', '-t', g:jukit_output_title, 'PageUp')
    endif
endfun

fun! jukit#tmux#splits#close_output_split() abort
    call jukit#tmux#cmd#tmux_command('kill-pane', '-t', g:jukit_output_title)
endfun

fun! jukit#tmux#splits#exists(...) abort
    let output_var_exists = exists('g:jukit_output_title')

    if output_var_exists
        let cmd_output = 'tmux has-session -t ' . g:jukit_output_title
        return !(system(cmd_output)=~"can't find pane")
    endif
    return 0
endfun
