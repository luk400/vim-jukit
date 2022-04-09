fun! s:system(arglist) abort
    if has('nvim')
        return system(a:arglist)
    else
        let args = a:arglist
        let cmd = join(args[:2], ' ')
        let cmd = cmd . ' ' . join(map(args[3:], {k,v -> shellescape(v)}), ' ')
        return system(cmd)
    endif
endfun

fun! jukit#kitty#cmd#invalid_version(vreq) abort
    let vcurrent = matchstr(s:system(['kitty', '--version']),
        \ '\%(kitty \)\@<=\(\d\{1,}\.\{0,1}\)\{1,}')
    let v_split = split(vcurrent, '\.')
    while len(v_split) < 3
        call add(v_split, 0)
    endwhile

    if !jukit#util#is_valid_version(v_split, a:vreq)
        return v_split
    endif

    return ''
endfun

fun! s:check_response(cmd, response) abort
    let invalid = a:response =~? 'unknown' || a:response =~? 'not.\{,5}valid' || a:response =~? 'traceback'
    if invalid
        echom '[vim-jukit] The following kitty command (may have) failed'
        echom '    COMMAND: `' . a:cmd . '`'
        echom '    -> RESPONSE: `' . a:response . '`'
        return v:null
    endif
    return a:response
endfun

fun! jukit#kitty#cmd#send_text(win_title, text) abort
    let text = a:text
    if !(matchstrpos(a:text, "\r$")[-1]>=0)
        let text = text . "\r"
    endif
    let cmd = ['kitty', '@', 'send-text', '--match', 'title:' . a:win_title, text]
    let response = s:system(cmd)
    return s:check_response(cmd, response)
endfun

fun! jukit#kitty#cmd#close_window(win_title) abort
    let cmd = ['kitty', '@', 'close-window', '--match', 'title:' . a:win_title]
    let response = s:system(cmd)
    return s:check_response(join(cmd, ' '), response)
endfun

fun! jukit#kitty#cmd#launch(win_title, ...) abort
    let cmd = ['kitty', '@', 'launch', '--title', a:win_title] + a:000
    let response = s:system(cmd)
    return s:check_response(join(cmd, ' '), response)
endfun

" general function to build a specific kitty command
fun! jukit#kitty#cmd#kitty_command(...) abort
    let cmd = ['kitty', '@'] + a:000
    let response = s:system(cmd)
    return s:check_response(join(cmd, ' '), response)
endfun
