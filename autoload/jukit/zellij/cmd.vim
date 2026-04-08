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

" Translate a tiled-style direction ('right'/'left'/'down'/'up') into
" --x/--y/--width/--height args for new-pane --floating, so a floating
" pane lands in the same screen quadrant the user expected when they
" set their direction config. Returns an empty list for unrecognized
" directions, which lets zellij fall back to its default centered
" placement.
fun! s:floating_position_args(direction) abort
    if a:direction ==# 'right'
        return ['--x', '50%', '--y', '0%',  '--width', '50%',  '--height', '100%']
    elseif a:direction ==# 'left'
        return ['--x', '0%',  '--y', '0%',  '--width', '50%',  '--height', '100%']
    elseif a:direction ==# 'down'
        return ['--x', '0%',  '--y', '50%', '--width', '100%', '--height', '50%']
    elseif a:direction ==# 'up'
        return ['--x', '0%',  '--y', '0%',  '--width', '100%', '--height', '50%']
    endif
    return []
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
"   was_floating = 1: pane is a pinned float; unpin first, then hide
"                    the float layer (hide-floating-panes is a no-op
"                    on pinned panes, so we have to unpin first).
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
        call jukit#zellij#cmd#zellij_command('hide-floating-panes')
    else
        " Float: the pane was created with --pinned true (Y05), and
        " hide-floating-panes does NOT affect pinned panes -- pinning
        " is the "always on top regardless of state" mechanism. So we
        " unpin first, then the global hide can reach our pane. After
        " hiding, the pane is in an unpinned-hidden state; the show
        " path below re-pins it on the way back.
        call jukit#zellij#cmd#zellij_command(
            \ 'toggle-pane-pinned', '--pane-id', a:pane_id)
        call jukit#zellij#cmd#zellij_command('hide-floating-panes')
    endif
    return 1
endfun

" Show a previously-hidden pane by id.
"   want_floating = 1: pane was pinned-float originally; bring the
"                     float layer back, then re-pin (so the next
"                     focus_vim doesn't auto-hide it).
"   want_floating = 0: pane was tiled originally; toggle it directly
"                     from hidden-floating back to embedded-tiled.
"
" Why we don't use show-floating-panes for the tiled case: that action
" is *tab-global* and would un-park EVERY hidden floating pane in the
" current tab, including parked panes belonging to other jukit
" sessions. The previously-active session's hidden output pane would
" then come back as a stray visible float on top of vim. Toggling
" embed-or-floating directly on the target pane id changes only that
" pane's container (hidden float -> tiled), without touching the
" float-layer visibility, so other parked panes stay where we left
" them.
fun! jukit#zellij#cmd#show_pane_by_id(pane_id, want_floating) abort
    if empty(a:pane_id)
        return v:null
    endif
    if a:want_floating
        " Float-mode pane: bring the float layer back. This still
        " unhides every unpinned float in the layer (including
        " unrelated ones), which is the documented caveat float-mode
        " users opted into. After the layer is back, re-pin our pane
        " so the next focus_vim() doesn't auto-hide it again. Then
        " focus vim explicitly because show-floating-panes auto-focuses
        " the topmost float, and the user's cursor should land in vim
        " after a <leader>os "show" toggle, not in the revealed pane.
        call jukit#zellij#cmd#zellij_command('show-floating-panes')
        call jukit#zellij#cmd#zellij_command(
            \ 'toggle-pane-pinned', '--pane-id', a:pane_id)
        call jukit#zellij#cmd#focus_vim()
    else
        " Tiled-mode pane that was parked via the float-layer trick:
        " toggle directly back to embedded. See block comment above.
        " After re-embedding, zellij leaves focus on the just-revealed
        " pane, which means the user's keystrokes would silently get
        " routed into the output pane instead of vim. Bounce focus
        " back to vim so the show is purely visual -- mirrors the
        " float branch above and cmd#launch's tail-call.
        call jukit#zellij#cmd#zellij_command(
            \ 'toggle-pane-embed-or-floating', '--pane-id', a:pane_id)
        call jukit#zellij#cmd#focus_vim()
    endif
    return 1
endfun

" Send `text` followed by Enter to a specific pane via --pane-id.
" No focus changes -- write-chars and write target the pane directly.
"
" The `pane_type` argument is one of:
"   - 'output': resolve to the active session's output pane id
"     (mirrors how the cross-backend dispatcher in send.vim calls us
"     with this literal alias).
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

" Resolve a pane_type alias to a concrete pane id. 'output' looks at
" the active session; anything else is taken as a literal id.
fun! s:resolve_pane_id(pane_type) abort
    if a:pane_type ==# 'output'
        let session = jukit#zellij#splits#_active_session()
        if type(session) == type(v:null) || empty(get(session, 'output_pane_id', ''))
            return ''
        endif
        return session.output_pane_id
    else
        " Treat as a literal pane id (e.g. "terminal_2") OR, for back
        " compat with code that still passes a title, fall through to
        " the active session's output id if it matches the title.
        let session = jukit#zellij#splits#_active_session()
        if type(session) != type(v:null)
            if a:pane_type ==# get(session, 'output_title', '')
                return get(session, 'output_pane_id', '')
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
" pane runs the given argv instead of the default shell. Pass an
" empty list (or omit) to get a default-shell pane.
"
" Optional a:2 = floating (0/1). When 1, the pane is created with
" `--floating` and the `direction` argument is ignored. When 0 (default),
" the pane is tiled and `--direction` is honored.
"
" Optional a:3 = position_override (list of position args, e.g.
" ['--x','50%','--y','50%','--width','50%','--height','50%']). Only
" honored when floating==1. Replaces the default direction-derived
" position.
fun! jukit#zellij#cmd#launch(direction, name, ...) abort
    if !s:in_zellij()
        echom '[vim-jukit] Not in a Zellij session!'
        return v:null
    endif

    let cmd_args = a:0 > 0 ? a:1 : []
    let floating = a:0 > 1 ? a:2 : 0
    let pos_override = a:0 > 2 ? a:3 : v:null

    let cmd = ['zellij', 'action', 'new-pane',
        \ '--name', a:name,
        \ '--cwd', getcwd()]

    if floating
        " --pinned true keeps the pane visible in the float layer
        " regardless of focus. Without it, the focus_vim() call below
        " would auto-hide the pane the moment we hand focus back to
        " vim, since zellij's default behavior is "floating panes
        " disappear when a tiled pane gains focus".
        "
        " The position args translate the user's direction config (e.g.
        " 'right') into a half-screen quadrant, otherwise zellij would
        " always center the float ignoring the configured direction.
        " The caller can pass an explicit pos_override to bypass the
        " direction-derived default.
        let cmd += ['--floating', '--pinned', 'true']
        if type(pos_override) == type([]) && !empty(pos_override)
            let cmd += pos_override
        else
            let cmd += s:floating_position_args(a:direction)
        endif
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
