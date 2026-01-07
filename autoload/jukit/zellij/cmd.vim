if !exists('g:jukit_zellij_output_direction')
    let g:jukit_zellij_output_direction = 'right'
endif
if !exists('g:jukit_zellij_outhist_direction')
    let g:jukit_zellij_outhist_direction = 'down'
endif

let g:jukit_zellij_vim_pane_id = $ZELLIJ_PANE_ID

let s:opposite_direction = {
    \ 'up': 'down',
    \ 'down': 'up',
    \ 'left': 'right',
    \ 'right': 'left'
    \ }

fun! s:system(arglist) abort
    if has('nvim')
        return system(a:arglist)
    else
        if type(a:arglist) == type([])
            let cmd = a:arglist[0] . ' ' . join(map(a:arglist[1:], {k,v -> shellescape(v)}), ' ')
        else
            let cmd = a:arglist
        endif
        return system(cmd)
    endif
endfun

fun! s:in_zellij() abort
    return !empty($ZELLIJ)
endfun

fun! s:check_response(cmd, response, quiet) abort
    if !s:in_zellij()
        if !a:quiet
            echom '[vim-jukit] Not in a Zellij session!'
        endif
        return v:null
    endif
    
    let has_error = a:response =~? 'error' || a:response =~? 'failed' || a:response =~? 'not found'
    if has_error
        if !a:quiet
            echom '[vim-jukit] Zellij command may have failed:'
            echom '    COMMAND: `' . a:cmd . '`'
            echom '    RESPONSE: `' . a:response . '`'
        endif
        return v:null
    endif
    return a:response
endfun

fun! jukit#zellij#cmd#zellij_command(...) abort
    if a:0 > 0 && a:1 ==# 'QUIET'
        let quiet = 1
        let args = a:000[1:]
    else
        let quiet = 0
        let args = a:000
    endif
    
    let cmd = ['zellij', 'action'] + args
    let response = s:system(cmd)
    return s:check_response(join(cmd, ' '), response, quiet)
endfun

fun! jukit#zellij#cmd#pane_exists_in_direction(direction) abort
    if !s:in_zellij()
        return 0
    endif
    
    let layout = s:system(['zellij', 'action', 'dump-layout'])
    let pane_count = len(split(layout, 'pane'))
    return pane_count > 1
endfun

fun! jukit#zellij#cmd#focus_pane(direction) abort
    return jukit#zellij#cmd#zellij_command('move-focus', a:direction)
endfun

fun! jukit#zellij#cmd#return_to_vim() abort
    return jukit#zellij#cmd#zellij_command('focus-previous-pane')
endfun

fun! jukit#zellij#cmd#send_text_to_direction(direction, text) abort
    if !s:in_zellij()
        echom '[vim-jukit] Not in a Zellij session!'
        return v:null
    endif
    
    let text = substitute(a:text, '\n$\|\r$', '', '')
    
    call jukit#zellij#cmd#zellij_command('move-focus', a:direction)
    
    sleep 50m
    
    call jukit#zellij#cmd#zellij_command('write-chars', text)
    call jukit#zellij#cmd#zellij_command('write', '13')
    
    sleep 50m
    call jukit#zellij#cmd#return_to_vim()
    
    return 1
endfun

fun! jukit#zellij#cmd#send_text(pane_type, text) abort
    if a:pane_type ==# 'output' || a:pane_type ==# g:jukit_output_title
        let direction = g:jukit_zellij_output_direction
    elseif a:pane_type ==# 'outhist' || a:pane_type ==# g:jukit_outhist_title
        let direction = g:jukit_zellij_outhist_direction
    else
        let direction = a:pane_type
    endif
    
    return jukit#zellij#cmd#send_text_to_direction(direction, a:text)
endfun

fun! jukit#zellij#cmd#send_text_no_enter(direction, text) abort
    if !s:in_zellij()
        return v:null
    endif
    
    call jukit#zellij#cmd#zellij_command('move-focus', a:direction)
    sleep 50m
    call jukit#zellij#cmd#zellij_command('write-chars', a:text)
    sleep 50m
    call jukit#zellij#cmd#return_to_vim()
    
    return 1
endfun

fun! jukit#zellij#cmd#launch(direction, ...) abort
    if !s:in_zellij()
        echom '[vim-jukit] Not in a Zellij session!'
        return v:null
    endif
    
    let cmd = ['zellij', 'action', 'new-pane', '--direction', a:direction]
    
    if a:0 > 0
        let cmd = cmd + a:000
    endif
    let response = s:system(cmd)
    
    sleep 200m
    call jukit#zellij#cmd#return_to_vim()

    return a:direction
endfun


fun! jukit#zellij#cmd#close_pane(direction) abort
    
    call jukit#zellij#cmd#zellij_command('move-focus', a:direction)
    sleep 50m
    
    call jukit#zellij#cmd#zellij_command('close-pane')
    
    return 1
endfun

fun! jukit#zellij#cmd#resize_pane(direction, ...) abort
    let amount = a:0 > 0 ? a:1 : 5
    let action = a:0 > 1 ? a:2 : 'increase'
    for i in range(amount)
        call jukit#zellij#cmd#zellij_command('resize', action, a:direction)
    endfor
endfun

fun! jukit#zellij#cmd#scroll_pane(pane_direction, scroll_action) abort
    
    call jukit#zellij#cmd#zellij_command('move-focus', a:pane_direction)
    sleep 50m
    
    if a:scroll_action ==# 'up'
        call jukit#zellij#cmd#zellij_command('scroll-up')
    elseif a:scroll_action ==# 'down'
        call jukit#zellij#cmd#zellij_command('scroll-down')
    elseif a:scroll_action ==# 'page-up'
        call jukit#zellij#cmd#zellij_command('page-scroll-up')
    elseif a:scroll_action ==# 'page-down'
        call jukit#zellij#cmd#zellij_command('page-scroll-down')
    elseif a:scroll_action ==# 'half-up'
        call jukit#zellij#cmd#zellij_command('half-page-scroll-up')
    elseif a:scroll_action ==# 'half-down'
        call jukit#zellij#cmd#zellij_command('half-page-scroll-down')
    elseif a:scroll_action ==# 'top'
        call jukit#zellij#cmd#zellij_command('scroll-to-top')
    elseif a:scroll_action ==# 'bottom'
        call jukit#zellij#cmd#zellij_command('scroll-to-bottom')
    endif
    
    sleep 50m
    call jukit#zellij#cmd#return_to_vim()
endfun

fun! jukit#zellij#cmd#enter_scroll_mode(pane_direction) abort
    call jukit#zellij#cmd#zellij_command('move-focus', a:pane_direction)
    call jukit#zellij#cmd#zellij_command('switch-mode', 'scroll')
endfun

fun! jukit#zellij#cmd#toggle_fullscreen() abort
    call jukit#zellij#cmd#zellij_command('toggle-fullscreen')
endfun

fun! jukit#zellij#cmd#get_current_pane_id() abort
    return $ZELLIJ_PANE_ID
endfun

fun! jukit#zellij#cmd#pane_exists(pane_type) abort
    if a:pane_type ==# 'output'
        return exists('g:jukit_output_title') && !empty(g:jukit_output_title)
    elseif a:pane_type ==# 'outhist'
        return exists('g:jukit_outhist_title') && !empty(g:jukit_outhist_title)
    endif
    return 0
endfun
