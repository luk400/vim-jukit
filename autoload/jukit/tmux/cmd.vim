fun! s:system(arglist) abort
    if has('nvim')
        return system(a:arglist)
    else
        let cmd = a:arglist[0] . ' ' . join(map(a:arglist[1:], {k,v -> shellescape(v)}), ' ')
        return system(cmd)
    endif
endfun

fun! s:check_response(cmd, response, quiet) abort
    if a:response =~? 'no server'
        if !a:quiet
            echom '[vim-jukit] Split not possible - start tmux before opening (n)vim!'
        endif
        return v:null
    elseif a:response =~? "can.*t find"
        if !a:quiet
            echom "[vim-jukit] Can't find pane!"
        endif
        return v:null
    endif
    let invalid = a:response =~? 'unknown' || a:response =~? 'traceback'
    if invalid
        if !a:quiet
            echom '[vim-jukit] The following tmux command (may have) failed'
            echom '    COMMAND: `' . a:cmd . '`'
            echom '    -> RESPONSE: `' . a:response . '`'
        endif
        return v:null
    endif
    return a:response
endfun

fun! s:tmux_property(property) abort
  return substitute(s:system("display -p '" . a:property . "'"), '\n$', '', '')
endfunction

fun! jukit#tmux#cmd#pane_exists(pane)
    let cmd = ['QUIET', 'send-keys', '-t', a:pane, '']
    let response = call('jukit#tmux#cmd#tmux_command', cmd)
    return !(type(response) == 7)
endfun

fun! jukit#tmux#cmd#send_text(pane, text) abort
    let text = substitute(a:text, '\n$\|\r$', ' ', '')
    let cmd = ['send-keys', '-t', a:pane, text, 'Enter']
    return call('jukit#tmux#cmd#tmux_command', cmd)
endfun

fun! jukit#tmux#cmd#launch(...) abort
    let cmd = ['tmux', 'split-window', '-P', '-F', '#{pane_id}'] + a:000
    let response = s:system(cmd)
    return s:check_response(join(cmd, ' '), response, 0)
endfun

" general function to build a specific tmux commands
fun! jukit#tmux#cmd#tmux_command(...) abort
    if a:0 > 0 && a:1 == 'QUIET'
        let quiet =  1
        let cmd = ['tmux'] + a:000[1:]
    else
        let quiet =  0
        let cmd = ['tmux'] + a:000
    endif
    let response = s:system(cmd)
    return s:check_response(join(cmd, ' '), response, quiet)
endfun
