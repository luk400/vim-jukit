fun! s:parse_layout(layout, output_exists, outhist_exists) abort
    let inner_pair = {}
    let outer_pane = {'split': a:layout['split'], 'bias': a:layout['p1']}
    
    if type(a:layout["val"][0]) == 4
        let d = a:layout["val"][0]
        let outer_pane['pane'] = a:layout["val"][1]
        let outer_pane['top_or_left'] = 0
        let inner_pair['pane'] = [d["val"][0], d["val"][1]]
    elseif type(a:layout["val"][1]) == 4
        let d = a:layout["val"][1]
        let outer_pane['pane'] = a:layout["val"][0]
        let outer_pane['top_or_left'] = 1
        let inner_pair['pane'] = [d["val"][0], d["val"][1]]
    else
        echom "[vim-jukit] Invalid layout dict!"
        return v:null
    endif
    
    let inner_pair['split'] = d["split"]
    let inner_pair['bias'] = d["p1"]
    
    return [inner_pair, outer_pane]
endfun

fun! s:get_pane_direction(name) abort
    if a:name ==# 'file_content'
        return 'vim'
    elseif a:name ==# 'output'
        return g:jukit_zellij_output_direction
    elseif a:name ==# 'output_history'
        return g:jukit_zellij_outhist_direction
    else
        return v:null
    endif
endfun

fun! s:resize_to_percentage(direction, percentage, split_type) abort
    if a:split_type ==# 'horizontal'
        if a:percentage > 0.5
            let resize_dir = (a:direction ==# 'right') ? 'right' : 'left'
        else
            let resize_dir = (a:direction ==# 'right') ? 'left' : 'right'
        endif
    else
        if a:percentage > 0.5
            let resize_dir = (a:direction ==# 'down') ? 'down' : 'up'
        else
            let resize_dir = (a:direction ==# 'down') ? 'up' : 'down'
        endif
    endif
    
    let diff = abs(a:percentage - 0.5)
    let steps = float2nr(diff * 20)  " ~20 steps for 50% change
    
    for i in range(steps)
        call jukit#zellij#cmd#zellij_command('resize', 'increase', resize_dir)
    endfor
endfun

fun! jukit#zellij#layouts#set_layout(layout) abort
    let output_exists = jukit#zellij#splits#exists('output')
    let outhist_exists = jukit#zellij#splits#exists('outhist')
    
    if !output_exists && !outhist_exists
        echom "[vim-jukit] No panes for layout present"
        return
    endif
    
    let response = s:parse_layout(a:layout, output_exists, outhist_exists)
    if type(response) == type(v:null)
        return
    endif
    
    let inner_pair = response[0]
    let outer_pane = response[1]
    
    if output_exists
        call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
        sleep 50m
        
        call s:resize_to_percentage(
            \ g:jukit_zellij_output_direction,
            \ outer_pane['bias'],
            \ outer_pane['split']
            \ )
        
        call jukit#zellij#cmd#return_to_vim()
    endif
    
    if output_exists && outhist_exists
        call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
        sleep 50m
        call jukit#zellij#cmd#focus_pane(g:jukit_zellij_outhist_direction)
        sleep 50m
        
        call s:resize_to_percentage(
            \ g:jukit_zellij_outhist_direction,
            \ inner_pair['bias'],
            \ inner_pair['split']
            \ )
        
        call jukit#zellij#cmd#return_to_vim()
        sleep 50m
        call jukit#zellij#cmd#return_to_vim()
    endif
endfun

fun! jukit#zellij#layouts#set_simple_layout(type) abort
    let output_exists = jukit#zellij#splits#exists('output')
    let outhist_exists = jukit#zellij#splits#exists('outhist')
    
    if !output_exists
        echom "[vim-jukit] Output pane required for layout"
        return
    endif
    
    if a:type ==# 'horizontal'
        call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
        sleep 50m
        
        for i in range(5)
            call jukit#zellij#cmd#zellij_command('resize', 'increase', 'left')
        endfor
        
        call jukit#zellij#cmd#return_to_vim()
        
    elseif a:type ==# 'vertical'
        call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
        sleep 50m
        
        for i in range(5)
            call jukit#zellij#cmd#zellij_command('resize', 'increase', 'up')
        endfor
        
        call jukit#zellij#cmd#return_to_vim()
        
    elseif a:type ==# 'stacked'
        echom "[vim-jukit] Stacked layout: use Zellij's native stacking (Ctrl+p, s)"
    endif
endfun

fun! jukit#zellij#layouts#toggle_fullscreen() abort
    call jukit#zellij#cmd#zellij_command('toggle-fullscreen')
endfun

fun! jukit#zellij#layouts#swap_panes() abort
    if !jukit#zellij#splits#exists('output') || !jukit#zellij#splits#exists('outhist')
        echom "[vim-jukit] Need both output and history panes to swap"
        return
    endif
    
    let temp = g:jukit_zellij_output_direction
    let g:jukit_zellij_output_direction = g:jukit_zellij_outhist_direction
    let g:jukit_zellij_outhist_direction = temp
    
    echom "[vim-jukit] Pane directions swapped (logical swap only)"
    echom "  Output direction: " . g:jukit_zellij_output_direction
    echom "  History direction: " . g:jukit_zellij_outhist_direction
endfun

fun! jukit#zellij#layouts#reset_layout() abort
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
    sleep 50m
    
    call jukit#zellij#cmd#zellij_command('toggle-fullscreen')
    sleep 100m
    call jukit#zellij#cmd#zellij_command('toggle-fullscreen')
    
    call jukit#zellij#cmd#return_to_vim()
endfun

fun! jukit#zellij#layouts#increase_output_size(steps) abort
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
    sleep 50m
    
    if g:jukit_zellij_output_direction ==# 'down'
        let resize_dir = 'up'
    elseif g:jukit_zellij_output_direction ==# 'up'
        let resize_dir = 'down'
    elseif g:jukit_zellij_output_direction ==# 'right'
        let resize_dir = 'left'
    else
        let resize_dir = 'right'
    endif
    
    for i in range(a:steps)
        call jukit#zellij#cmd#zellij_command('resize', 'increase', resize_dir)
    endfor
    
    call jukit#zellij#cmd#return_to_vim()
endfun

fun! jukit#zellij#layouts#decrease_output_size(steps) abort
    call jukit#zellij#cmd#focus_pane(g:jukit_zellij_output_direction)
    sleep 50m
    
    if g:jukit_zellij_output_direction ==# 'down'
        let resize_dir = 'down'
    elseif g:jukit_zellij_output_direction ==# 'up'
        let resize_dir = 'up'
    elseif g:jukit_zellij_output_direction ==# 'right'
        let resize_dir = 'right'
    else
        let resize_dir = 'left'
    endif
    
    for i in range(a:steps)
        call jukit#zellij#cmd#zellij_command('resize', 'decrease', resize_dir)
    endfor
    
    call jukit#zellij#cmd#return_to_vim()
endfun
