fun! s:get_pane_by_name(name, output_exists, outhist_exists) abort
    if a:name == 'file_content'
        let current_pane = matchstr(system('tmux run "echo #{pane_id}"'), '%\d*')
        return current_pane
    elseif a:name == 'output' && a:output_exists
        return g:jukit_output_title
    elseif a:name == 'output_history' && a:outhist_exists
        return g:jukit_outhist_title
    else
        return -1
    endif
endfun

fun! s:parse_layout(layout, op, oh) abort
    let inner_pair = {}
    let outer_pane = {'split': a:layout['split'], 'bias': a:layout['p1']}

    if type(a:layout["val"][0]) == 4
        let d = a:layout["val"][0]
        let outer_pane['pane'] = s:get_pane_by_name(a:layout["val"][1], a:op, a:oh)
        let outer_pane['top_or_left'] = 0
        let inner_pair['pane'] = [s:get_pane_by_name(d["val"][0], a:op, a:oh), 
            \ s:get_pane_by_name(d["val"][1], a:op, a:oh)]
    elseif type(a:layout["val"][1]) == 4
        let d = a:layout["val"][1]
        let outer_pane['pane'] = s:get_pane_by_name(a:layout["val"][0], a:op, a:oh)
        let outer_pane['top_or_left'] = 1
        let inner_pair['pane'] = [s:get_pane_by_name(d["val"][0], a:op, a:oh),
            \ s:get_pane_by_name(d["val"][1], a:op, a:oh)]
    else
        echom "[vim-jukit] Invalid layout dict!"
        return v:null
    endif

    let inner_pair['split'] = d["split"]
    let inner_pair['bias'] = d["p1"]

    return [inner_pair, outer_pane]
endfun

fun! s:setup_outer_split(outer_pane, panes_filtered, main_pane, outer_first) abort
    if a:outer_pane['pane'] == -1
        return
    endif

    if a:outer_pane['split'] == "horizontal"
        let cmd_flag = '-hdf'
        let resize_flag = '-x'
    else
        let cmd_flag = '-vdf'
        let resize_flag = '-y'
    endif

    if a:outer_first
        let cmd_flag = cmd_flag . 'b'
        let bias = float2nr((a:outer_pane['bias']) * 100) . '%'
    else
        let bias = float2nr((1-a:outer_pane['bias']) * 100) . '%'
    endif

    call jukit#tmux#cmd#tmux_command('move-pane', cmd_flag, '-s', 
        \ a:outer_pane['pane'], '-t', a:panes_filtered[0])
    call jukit#tmux#cmd#tmux_command('resize-pane', '-t', 
        \ a:outer_pane['pane'], resize_flag, bias)
    call jukit#tmux#cmd#tmux_command('select-pane', '-t', a:main_pane)
endfun

fun! s:setup_inner_split(outer_pane, inner_pair, panes_filtered, main_pane, outer_first) abort
    if !(len(a:panes_filtered) > 1)
        return
    endif

    if a:outer_pane['split'] == a:inner_pair['split'] && a:outer_first
        let factor = (1-a:outer_pane['bias'])
    elseif a:outer_pane['split'] == a:inner_pair['split']
        let factor = a:outer_pane['bias']
    else
        let factor = 1
    endif

    let bias = float2nr(a:inner_pair['bias'] * factor * 100) . '%'
    if a:inner_pair['split'] == "horizontal"
        let cmd_flag = '-hd'
        let resize_flag = '-x'
    else
        let cmd_flag = '-vd'
        let resize_flag = '-y'
    endif
    call jukit#tmux#cmd#tmux_command('move-pane', cmd_flag, '-s', 
        \ a:panes_filtered[1], '-t', a:panes_filtered[0])
    call jukit#tmux#cmd#tmux_command('resize-pane', '-t', a:panes_filtered[0],
        \ resize_flag, bias)
    call jukit#tmux#cmd#tmux_command('select-pane', '-t', a:main_pane)
endfun

fun! jukit#tmux#layouts#set_layout(layout) abort
    let output_exists = jukit#tmux#splits#exists('output')
    let outhist_exists = jukit#tmux#splits#exists('outhist')
    if !output_exists && !outhist_exists
        echom "[vim-jukit] No windows for layout present"
        return
    elseif !output_exists || !outhist_exists
        let only_one = 1
    else
        let only_one = 0
    endif

    let response = s:parse_layout(a:layout, output_exists, outhist_exists)
    let main_pane = s:get_pane_by_name('file_content', -1, -1)

    if type(a:layout['val'][0]) == 1
        let outer_first = 1
    else
        let outer_first = 0
    endif

    if type(response) == 7
        return
    endif

    let inner_pair = response[0]
    let outer_pane = response[1]

    let panes_filtered = filter(copy(inner_pair['pane']), {k,v -> v != -1})

    call s:setup_outer_split(outer_pane, panes_filtered, main_pane, outer_first)
    call s:setup_inner_split(outer_pane, inner_pair, panes_filtered, main_pane, outer_first)
endfun
