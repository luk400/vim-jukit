" =====================================================================
" Pane targeting layer for the zellij backend.
"
" zellij 0.44+ has no name-based pane focus action. Instead, every
" interesting action accepts a `--pane-id <id>` flag, and `new-pane`
" prints the new pane's id (in the form `terminal_<n>` or `plugin_<n>`)
" to stdout on success. So our identity model is:
"
"   1. We assign a unique --name on creation (still useful: zellij shows
"      it in the pane frame, and dump-layout includes it for our
"      reality-based exists() check).
"   2. We capture the pane id from `new-pane`'s stdout and store it in
"      the session dict alongside the name.
"   3. From then on, every action targets the pane by its id via
"      `--pane-id <id>` (write-chars, close-pane, toggle-pane-embed-or-
"      floating, etc.) or via `focus-pane-id <id>` (positional). No
"      focus dance, no return-to-vim shuffle for sends.
"
" The vim pane itself is identified by $ZELLIJ_PANE_ID, which zellij
" sets as a bare integer (e.g. "0"). focus-pane-id accepts both forms
" ("0" and "terminal_0"); we pass whatever is in $ZELLIJ_PANE_ID.
"
" If your zellij version uses different flag/subcommand names, the only
" places you need to update are jukit#zellij#cmd#focus_vim,
" jukit#zellij#cmd#focus_pane_by_id, and the new-pane invocation in
" jukit#zellij#cmd#launch (plus its stdout-parsing in s:extract_pane_id).
" =====================================================================

" Lazy capture of $ZELLIJ_PANE_ID. Re-captures if $ZELLIJ has changed since
" last capture, so re-attaching to a different session does the right thing.
fun! jukit#zellij#cmd#vim_pane_id() abort
    if !exists('s:vim_pane_id') || get(s:, 'vim_session', '') !=# $ZELLIJ
        let s:vim_pane_id = $ZELLIJ_PANE_ID
        let s:vim_session = $ZELLIJ
    endif
    return s:vim_pane_id
endfun

" Backwards-compat global; some old user configs may reference it.
let g:jukit_zellij_vim_pane_id = $ZELLIJ_PANE_ID

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

    " Match concrete zellij error tokens at line start, plus 'panicked' / 'cannot find pane'.
    " The previous broad substring match produced false positives on legitimate output.
    let has_error = a:response =~? '\(^\|\n\)\s*\(error\|failed\)\>'
        \ || a:response =~? 'panicked\|cannot find pane'
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

" Extract a pane id (form `terminal_<n>` or `plugin_<n>`) from a chunk of
" zellij stdout. Returns the *last* match, since `new-pane` prints exactly
" one such token followed by a newline. Returns '' on no match.
fun! s:extract_pane_id(stdout) abort
    let m = matchstr(a:stdout, '\(terminal\|plugin\)_\d\+')
    return m
endfun

" Focus the vim pane via its captured pane id. The vim pane id comes
" from $ZELLIJ_PANE_ID, which zellij sets as a bare integer; focus-pane-id
" accepts that form as a shorthand for terminal_<n>.
fun! jukit#zellij#cmd#focus_vim() abort
    let vim_id = jukit#zellij#cmd#vim_pane_id()
    if empty(vim_id)
        return jukit#zellij#cmd#zellij_command('focus-previous-pane')
    endif
    return jukit#zellij#cmd#zellij_command('focus-pane-id', vim_id)
endfun

" Focus an arbitrary pane by its id (e.g. "terminal_2" or "2").
fun! jukit#zellij#cmd#focus_pane_by_id(pane_id) abort
    if empty(a:pane_id)
        return v:null
    endif
    return jukit#zellij#cmd#zellij_command('focus-pane-id', a:pane_id)
endfun

" =====================================================================
" Hide / show pane helpers (zellij has no native "hide a tiled pane"
" action, so we lean on toggle-pane-embed-or-floating + the dedicated
" hide/show-floating-panes actions for the tiled-mode case). See plan
" section B.2.
"
" `was_floating` / `want_floating` describe the user's mode for the pane
" (1 = pane was created with --floating, 0 = pane was created tiled).
" The hide / show flow branches on it: float-mode is one action,
" tiled-mode requires an embed-to-float round-trip.
"
" `hide-floating-panes` and `show-floating-panes` are tab-global: they
" affect ALL floating panes in the current tab, not just ours. If the
" user has unrelated floating panes, they get toggled too. This is
" documented in the README; we don't have a finer-grained primitive in
" zellij as of 0.44.x.
" =====================================================================

" Hide a pane by id.
"   was_floating = 1: pane is floating; hide the float layer.
"   was_floating = 0: pane is tiled; convert to floating, then hide layer.
fun! jukit#zellij#cmd#hide_pane_by_id(pane_id, was_floating) abort
    if empty(a:pane_id)
        return v:null
    endif
    if !a:was_floating
        " Tiled: convert to floating first so we can hide it via the
        " global float-layer toggle. The pane process keeps running in
        " the (now invisible) float layer with all its state intact.
        call jukit#zellij#cmd#zellij_command(
            \ 'toggle-pane-embed-or-floating', '--pane-id', a:pane_id)
    endif
    call jukit#zellij#cmd#zellij_command('hide-floating-panes')
    return 1
endfun

" Show a previously-hidden pane by id.
"   want_floating = 1: pane stays floating; just bring float layer back.
"   want_floating = 0: pane was tiled originally; bring float layer back,
"     then convert it back to tiled.
fun! jukit#zellij#cmd#show_pane_by_id(pane_id, want_floating) abort
    if empty(a:pane_id)
        return v:null
    endif
    " Bring the float layer back so the pane is reachable.
    call jukit#zellij#cmd#zellij_command('show-floating-panes')
    if !a:want_floating
        " Tiled mode: convert back from floating to embedded.
        call jukit#zellij#cmd#zellij_command(
            \ 'toggle-pane-embed-or-floating', '--pane-id', a:pane_id)
    endif
    return 1
endfun

" Send `text` followed by Enter to a specific pane via --pane-id.
" No focus changes -- write-chars and write target the pane directly.
"
" The `pane_type` argument is one of:
"   - 'output' / 'outhist': resolve to the active session's matching
"     pane id (mirrors how the cross-backend dispatcher in send.vim
"     calls us with these literal aliases).
"   - any other string: treated as a pane id directly.
fun! jukit#zellij#cmd#send_text(pane_type, text) abort
    if !s:in_zellij()
        echom '[vim-jukit] Not in a Zellij session!'
        return v:null
    endif

    let pane_id = s:resolve_pane_id(a:pane_type)
    if empty(pane_id)
        return v:null
    endif

    let text = substitute(a:text, '\n$\|\r$', '', '')
    call jukit#zellij#cmd#zellij_command(
        \ 'write-chars', '--pane-id', pane_id, text)
    call jukit#zellij#cmd#zellij_command(
        \ 'write', '--pane-id', pane_id, '13')
    return 1
endfun

" Resolve a pane_type alias to a concrete pane id. 'output' / 'outhist'
" look at the active session; anything else is taken as an id directly.
fun! s:resolve_pane_id(pane_type) abort
    if a:pane_type ==# 'output'
        let session = jukit#zellij#splits#_active_session()
        if type(session) == type(v:null) || empty(get(session, 'output_pane_id', ''))
            return ''
        endif
        return session.output_pane_id
    elseif a:pane_type ==# 'outhist'
        let session = jukit#zellij#splits#_active_session()
        if type(session) == type(v:null) || empty(get(session, 'outhist_pane_id', ''))
            return ''
        endif
        return session.outhist_pane_id
    else
        " Treat as a literal pane id (e.g. "terminal_2") OR, for back
        " compat with code that still passes a title, fall through to
        " the active session's output id if it matches the title.
        let session = jukit#zellij#splits#_active_session()
        if type(session) != type(v:null)
            if a:pane_type ==# get(session, 'output_title', '')
                return get(session, 'output_pane_id', '')
            elseif a:pane_type ==# get(session, 'outhist_title', '')
                return get(session, 'outhist_pane_id', '')
            endif
        endif
        return a:pane_type
    endif
endfun

" Launch a new zellij pane in `direction`, tagged with `name`. Captures
" the new pane's id from new-pane's stdout (format `terminal_<n>` or
" `plugin_<n>`) and returns it. Returns v:null on failure.
"
" Optional a:1 = cmd_args (list of strings) appended after `--` so the
" pane runs the given argv instead of the default shell. Used by the
" outhist viewer to spawn a python script directly in the pane. Pass an
" empty list (or omit) to get a default-shell pane.
"
" Optional a:2 = floating (0/1). When 1, the pane is created with
" `--floating` and the `direction` argument is ignored. When 0 (default),
" the pane is tiled and `--direction` is honored.
fun! jukit#zellij#cmd#launch(direction, name, ...) abort
    if !s:in_zellij()
        echom '[vim-jukit] Not in a Zellij session!'
        return v:null
    endif

    let cmd_args = a:0 > 0 ? a:1 : []
    let floating = a:0 > 1 ? a:2 : 0

    let cmd = ['zellij', 'action', 'new-pane',
        \ '--name', a:name,
        \ '--cwd', getcwd()]

    if floating
        let cmd += ['--floating']
    else
        let cmd += ['--direction', a:direction]
    endif

    if !empty(cmd_args)
        let cmd += ['--'] + cmd_args
    endif
    let response = s:system(cmd)
    if type(s:check_response(join(cmd, ' '), response, 0)) == type(v:null)
        return v:null
    endif

    " new-pane prints the new pane id to stdout on success, e.g.
    " "terminal_2\n". Capture it.
    let pane_id = s:extract_pane_id(response)
    if empty(pane_id)
        echom '[vim-jukit] launch: could not parse pane id from new-pane stdout: '
            \ . substitute(response, '\n', '\\n', 'g')
        return v:null
    endif

    " Brief settle so the spawned process has a chance to be ready before
    " the caller sends keystrokes. The pane id is already valid at this
    " point, but the process inside might not have finished initializing.
    sleep 200m
    call jukit#zellij#cmd#focus_vim()

    return pane_id
endfun
