fun! s:get_pane_by_name(name, output_exists) abort
    if a:name == 'file_content'
        let current_pane = matchstr(system('tmux run "echo #{pane_id}"'), '%\d*')
        return current_pane
    elseif a:name == 'output' && a:output_exists
        return g:jukit_output_title
    else
        return -1
    endif
endfun

" Set up a two-pane tmux layout: file_content + output. Layout dict
" shape: {'split': 'horizontal'|'vertical', 'p1': 0.0..1.0, 'val':
" [pane1, pane2]} where each entry is the literal string 'file_content'
" or 'output'.
fun! jukit#tmux#layouts#set_layout(layout) abort
    let output_exists = jukit#tmux#splits#exists('output')
    if !output_exists
        echom "[vim-jukit] No output pane present for layout"
        return
    endif

    if type(a:layout['val'][0]) != 1 || type(a:layout['val'][1]) != 1
        echom "[vim-jukit] Invalid layout dict: expected two named panes"
        return
    endif

    let main_pane = s:get_pane_by_name('file_content', output_exists)
    let pane_a = s:get_pane_by_name(a:layout['val'][0], output_exists)
    let pane_b = s:get_pane_by_name(a:layout['val'][1], output_exists)
    if pane_a == -1 || pane_b == -1
        return
    endif

    " Pane A is on the left/top side, pane B is on the right/bottom side.
    " p1 is the fractional size of pane A.
    if a:layout['split'] == "horizontal"
        let cmd_flag = '-hdfb'
        let resize_flag = '-x'
    else
        let cmd_flag = '-vdfb'
        let resize_flag = '-y'
    endif

    let bias = float2nr(a:layout['p1'] * 100) . '%'
    call jukit#tmux#cmd#tmux_command('move-pane', cmd_flag, '-s',
        \ pane_a, '-t', pane_b)
    call jukit#tmux#cmd#tmux_command('resize-pane', '-t',
        \ pane_a, resize_flag, bias)
    call jukit#tmux#cmd#tmux_command('select-pane', '-t', main_pane)
endfun
