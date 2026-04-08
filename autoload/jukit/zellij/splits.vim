" Cached `zellij action list-panes --json` output. list-panes is the
" authoritative source of "what panes currently exist with what titles":
" dump-layout only contains the layout *template* and doesn't surface
" runtime-set names from --name. We cache the parsed result for a short
" window so a flurry of jukit#zellij#splits#exists() calls (which the
" dispatcher and send code make a lot of) doesn't fork zellij a dozen
" times in a row. Cache must be invalidated on every state-mutating
" function below.
let s:exists_cache = []
let s:exists_cache_time = []

fun! jukit#zellij#splits#_list_panes_cached() abort
    if !empty(s:exists_cache_time)
        \ && reltimefloat(reltime(s:exists_cache_time)) < 0.2
        return s:exists_cache
    endif
    let raw = system('zellij action list-panes --json 2>&1')
    try
        let s:exists_cache = json_decode(raw)
        if type(s:exists_cache) != type([])
            let s:exists_cache = []
        endif
    catch
        let s:exists_cache = []
    endtry
    let s:exists_cache_time = reltime()
    return s:exists_cache
endfun

fun! jukit#zellij#splits#_invalidate_cache() abort
    let s:exists_cache_time = []
endfun

" Returns 1 if the given pane_id (in our canonical prefixed form, e.g.
" "terminal_2" or "plugin_0") matches any currently-existing pane in
" the (cached) list-panes output, else 0.
"
" list-panes --json gives us each pane's bare integer id and a separate
" `is_plugin` flag, so we reconstruct the prefixed form on the fly.
fun! jukit#zellij#splits#_pane_with_id_exists(pane_id) abort
    if empty(a:pane_id)
        return 0
    endif
    let panes = jukit#zellij#splits#_list_panes_cached()
    for p in panes
        let prefix = get(p, 'is_plugin', 0) ? 'plugin_' : 'terminal_'
        let id_str = prefix . string(get(p, 'id', ''))
        if id_str ==# a:pane_id
            return 1
        endif
        " Also accept bare-integer shorthand (e.g. "2" for "terminal_2"),
        " in case anything ever stores the id without the prefix.
        if !get(p, 'is_plugin', 0) && string(get(p, 'id', '')) ==# a:pane_id
            return 1
        endif
    endfor
    return 0
endfun

" =====================================================================
" Per-buffer named-session model.
"
" Each buffer has its own list of jukit "sessions" stored in
" b:jukit_sessions. A session is just a named output pane that may
" currently exist or not, and may currently be visible or hidden.
" b:jukit_active_session indexes into the list (or is -1 if no session
" has been created yet).
"
" The "active" session's output_title is mirrored to the legacy global
" g:jukit_output_title so that the cross-backend dispatcher in
" autoload/jukit/send.vim continues to work without modification: it
" always talks to the active session's output pane.
"
" A BufEnter autocmd (S06) re-syncs the global when the user moves
" between buffers, so each buffer remembers its own active session.
" =====================================================================

" Lazy-initialize b:jukit_sessions for the current buffer. Idempotent.
fun! jukit#zellij#splits#_session_init() abort
    if !exists('b:jukit_sessions')
        let b:jukit_sessions = []
    endif
    if !exists('b:jukit_active_session')
        let b:jukit_active_session = -1
    endif
endfun

" Return the currently-active session dict for this buffer, or v:null if
" there is no active session. The dict is mutable -- callers can update
" e.g. output_visible directly on the returned reference.
fun! jukit#zellij#splits#_active_session() abort
    call jukit#zellij#splits#_session_init()
    if b:jukit_active_session < 0 || b:jukit_active_session >= len(b:jukit_sessions)
        return v:null
    endif
    return b:jukit_sessions[b:jukit_active_session]
endfun

" Set the active session by index and sync the legacy g: global.
" Pass -1 to clear the active session entirely.
fun! jukit#zellij#splits#_set_active_session(idx) abort
    call jukit#zellij#splits#_session_init()
    let b:jukit_active_session = a:idx
    if a:idx < 0 || a:idx >= len(b:jukit_sessions)
        unlet! g:jukit_output_title
        return
    endif
    let session = b:jukit_sessions[a:idx]
    let session.last_used = localtime()
    let g:jukit_output_title = session.output_title
    call jukit#zellij#splits#_invalidate_cache()
endfun

" Re-sync the legacy globals from this buffer's active session. Called
" from a BufEnter autocmd (see plugin/jukit.vim) so that switching
" between buffers automatically points the cross-backend dispatcher at
" the right pane. No-op if the buffer has no sessions.
fun! jukit#zellij#splits#_sync_globals_from_buffer() abort
    if !exists('b:jukit_sessions') || !exists('b:jukit_active_session')
        return
    endif
    if b:jukit_active_session < 0 || b:jukit_active_session >= len(b:jukit_sessions)
        unlet! g:jukit_output_title
        return
    endif
    let session = b:jukit_sessions[b:jukit_active_session]
    let g:jukit_output_title = session.output_title
endfun

" Create a new session entry with the given user-supplied name. The
" output pane title is derived from the name plus a unique-id suffix so
" multiple sessions can share a display name without colliding in
" zellij. The new session has no pane yet (output_visible = -1 and
" output_pane_id empty until cmd#launch returns one). Returns the
" session index. Becomes the active session as a side effect.
fun! jukit#zellij#splits#_create_session(name) abort
    call jukit#zellij#splits#_session_init()
    let uid = jukit#util#get_unique_id()
    let session = {
        \ 'name':            a:name,
        \ 'output_title':    'jukit_output_' . uid,
        \ 'output_pane_id':  '',
        \ 'output_visible':  -1,
        \ 'output_float':    0,
        \ 'last_used':       localtime(),
        \ }
    call add(b:jukit_sessions, session)
    let idx = len(b:jukit_sessions) - 1
    call jukit#zellij#splits#_set_active_session(idx)
    return idx
endfun

" =====================================================================
" Hide / show wrappers for the active session's output pane.
"
" Thin glue between the session model (which carries the
" output_visible flag) and the cmd.vim primitives (which know how to
" actually flip pane visibility in zellij). Each wrapper updates the
" session dict's flag after the cmd succeeds.
"
" The functions are no-ops if there's no active session or the output
" pane doesn't exist.
"
" Each wrapper reads the per-pane float flag from the session dict
" instead of from g:jukit_output_float, so a pane that was created
" floating gets hidden via the float-mode path even if the global flag
" has since changed.
" =====================================================================

fun! jukit#zellij#splits#hide_output() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || session.output_visible != 1
        return
    endif
    call jukit#zellij#cmd#hide_pane_by_id(
        \ session.output_pane_id, get(session, 'output_float', g:jukit_output_float))
    let session.output_visible = 0
    call jukit#zellij#splits#_invalidate_cache()
endfun

fun! jukit#zellij#splits#show_output() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || session.output_visible != 0
        return
    endif
    let output_float = get(session, 'output_float', g:jukit_output_float)
    " Pin pre-show focus to vim so toggle-pane-embed-or-floating
    " inserts output adjacent to vim (matching what new-pane
    " --direction right does during initial creation).
    if !output_float
        call jukit#zellij#cmd#focus_vim()
    endif
    call jukit#zellij#cmd#show_pane_by_id(
        \ session.output_pane_id, output_float)
    let session.output_visible = 1
    call jukit#zellij#splits#_invalidate_cache()
endfun

" Wait for the named jukit pane to actually show up in dump-layout. Returns
" 1 on success, 0 on timeout. Each iteration invalidates the dump-layout
" cache so we get a fresh read.
fun! s:wait_for_pane(pane_type, num_tries, delay) abort
    let n = a:num_tries
    while n > 0
        call jukit#zellij#splits#_invalidate_cache()
        if jukit#zellij#splits#exists(a:pane_type)
            redraw!
            echo ''
            return 1
        endif
        let n -= 1
        redraw!
        echo '[vim-jukit] Waiting for Zellij pane...'
        exe 'sleep ' . a:delay . 'm'
    endwhile
    redraw!
    echo ''
    return 0
endfun

" =====================================================================
" Session switching.
"
" Bound to <leader>ss by default (configurable via
" g:jukit_session_switch_keybind in plugin/jukit.vim). Opens a picker
" listing all sessions in this buffer (sorted by last_used desc) plus
" a "Create new..." entry at the bottom. Switching to an existing
" session preserves the current visibility shape: if the OLD active
" session had output visible, the NEW active session's output gets
" shown too (creating it if needed).
" =====================================================================

fun! jukit#zellij#splits#switch_session() abort
    call jukit#zellij#splits#_session_init()

    " Build picker items: existing sessions sorted by last_used desc,
    " plus the create-new sentinel at the bottom.
    let n = len(b:jukit_sessions)
    let order = range(n)
    call sort(order, {a, b -> b:jukit_sessions[b].last_used - b:jukit_sessions[a].last_used})
    let items = []
    for idx in order
        let s = b:jukit_sessions[idx]
        let marker = (idx == b:jukit_active_session) ? ' (active)' : ''
        call add(items, s.name . marker)
    endfor
    call add(items, 'Create new...')

    " Snapshot what was visible in the OLD active session BEFORE the
    " picker pops, so we can mirror the same shape into whatever the
    " user lands on. We have to capture this now (in a closure-like
    " dict) because the floating dialog is async and the active session
    " could in principle change between dialog open and dialog submit.
    let old = jukit#zellij#splits#_active_session()
    let snap = {
        \ 'order':        order,
        \ 'items_count':  len(items),
        \ 'want_output':  type(old) != type(v:null) && old.output_visible == 1,
        \ }

    call jukit#util#select_session(items,
        \ {pick -> s:after_switch_pick(pick, snap)})
endfun

" Continuation: the user picked an entry in the session picker (or
" cancelled). Branches into 'create new' or 'switch to existing'.
fun! s:after_switch_pick(pick, snap) abort
    if a:pick < 0
        return
    endif

    " "Create new..." sentinel is the last item.
    if a:pick == a:snap.items_count - 1
        let default_name = jukit#util#get_unique_id()
        " Re-bind a:snap into a plain local so the lambda below
        " captures it via the standard local-variable closure path
        " (vimscript closures don't reliably reach into enclosing a:).
        let snap = a:snap
        call jukit#util#prompt_session_name(default_name,
            \ {n -> s:after_switch_create_new(n, snap)})
        return
    endif

    " Existing session selected. Map picker index back to the real
    " b:jukit_sessions index via the sorted order.
    let new_idx = a:snap.order[a:pick]
    if new_idx == b:jukit_active_session
        return
    endif

    " Hide the OLD session's output pane if it was visible.
    if a:snap.want_output
        call jukit#zellij#splits#hide_output()
    endif

    call jukit#zellij#splits#_set_active_session(new_idx)

    " Mirror the OLD session's output visibility into the NEW session.
    " If the NEW session has an output pane already, just unhide it. If
    " it doesn't have one yet, create it now so the swap actually
    " produces visible state for the user.
    if a:snap.want_output
        let s = jukit#zellij#splits#_active_session()
        if s.output_visible == 0
            call jukit#zellij#splits#show_output()
        elseif s.output_visible == -1
            call jukit#zellij#splits#_create_output_pane()
        endif
    endif
endfun

" Continuation: the user picked "Create new..." and supplied a name
" for the brand new session. Hide whatever the OLD active had visible,
" allocate the new session, and immediately auto-spawn an output pane
" if the OLD active had one -- the user expects an instantly-usable
" session, not one they have to <leader>os into manually right after
" creation (Y03).
fun! s:after_switch_create_new(name, snap) abort
    if empty(a:name)
        return
    endif

    if a:snap.want_output
        call jukit#zellij#splits#hide_output()
    endif

    call jukit#zellij#splits#_create_session(a:name)

    if a:snap.want_output
        call jukit#zellij#splits#_create_output_pane()
    endif
endfun

" Internal: actually create the output pane for the active session.
" Spawns it (floating or tiled per g:jukit_output_float), captures the
" pane id from cmd#launch's stdout, sends the optional initial command +
" the shell init, and updates the session's output_visible flag.
" Returns 1 on success, 0 on failure.
fun! jukit#zellij#splits#_create_output_pane(...) abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null)
        echom '[vim-jukit] _create_output_pane called with no active session'
        return 0
    endif

    " Mirror the session's title to the legacy global so the cross-backend
    " dispatcher in send.vim has a meaningful value to pass through.
    let g:jukit_output_title = session.output_title
    call jukit#zellij#splits#_invalidate_cache()

    let pane_id = jukit#zellij#cmd#launch(
        \ g:jukit_zellij_output_direction,
        \ session.output_title,
        \ [],
        \ g:jukit_output_float)
    if type(pane_id) == type(v:null)
        echom '[vim-jukit] Failed to create output pane'
        return 0
    endif

    let session.output_pane_id = pane_id
    let session.output_visible = 1
    let session.output_float = g:jukit_output_float
    call s:wait_for_pane('output', 8, 50)

    if a:0 > 0
        call jukit#zellij#cmd#send_text('output', a:1)
    endif

    if !g:jukit_inline_plotting && !g:jukit_save_output
        call jukit#zellij#cmd#send_text('output', g:jukit_shell_cmd)
        return 1
    endif

    call jukit#zellij#cmd#send_text('output', jukit#splits#_build_shell_cmd())
    call jukit#util#ipython_info_write({'terminal': 'zellij', 'import_complete': 0})
    return 1
endfun

" Tri-state output entry point. The behavior depends on what the active
" session looks like:
"
"   no session OR session has no output pane:
"       prompt for a session name (creating a new session if none),
"       then create the output pane within it.
"   session output exists and is visible:
"       hide it (toggle off).
"   session output exists and is hidden:
"       show it (toggle on).
"
" The optional a:1 is forwarded to _create_output_pane as an initial
" command sent to the new pane (used by the JukitOut user command).
"
" The "no session" branch is async because the session-name prompt is
" a floating-window dialog. The other branches stay synchronous --
" they don't need user input.
fun! jukit#zellij#splits#output(...) abort
    call jukit#zellij#splits#_session_init()
    let session = jukit#zellij#splits#_active_session()

    " Branch 1: no active session at all -- prompt asynchronously and
    " create the session + output pane in the continuation.
    if type(session) == type(v:null)
        let default_name = jukit#util#get_unique_id()
        let extra_args = a:000
        call jukit#util#prompt_session_name(default_name,
            \ {n -> s:after_output_session_name(n, extra_args)})
        return
    endif

    " Branch 2: active session exists but its output pane doesn't (yet).
    " This happens after "Create new" via the session picker, where the
    " session entry is allocated but no pane has been spawned yet.
    if session.output_visible == -1
        call call('jukit#zellij#splits#_create_output_pane', a:000)
        return
    endif

    " Branch 3: pane exists and is visible -- hide.
    if session.output_visible == 1
        call jukit#zellij#splits#hide_output()
        return
    endif

    " Branch 4: pane exists and is hidden -- show.
    if session.output_visible == 0
        call jukit#zellij#splits#show_output()
        return
    endif
endfun

" Continuation for splits#output's "no active session" branch. Called
" by the floating-input dialog after the user enters (or cancels) a
" session name.
fun! s:after_output_session_name(name, extra_args) abort
    if empty(a:name)
        echom '[vim-jukit] session creation cancelled'
        return
    endif
    call jukit#zellij#splits#_create_session(a:name)
    call call('jukit#zellij#splits#_create_output_pane', a:extra_args)
endfun

" Internal: create a terminal pane (no ipython, no shell init) for the
" active session. Like _create_output_pane but skips the shell init and
" ipython_info_write because the user wants a raw shell.
fun! jukit#zellij#splits#_create_term_pane() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null)
        echom '[vim-jukit] _create_term_pane called with no active session'
        return 0
    endif

    let g:jukit_output_title = session.output_title
    call jukit#zellij#splits#_invalidate_cache()

    let pane_id = jukit#zellij#cmd#launch(
        \ g:jukit_zellij_output_direction,
        \ session.output_title,
        \ [],
        \ g:jukit_output_float)
    if type(pane_id) == type(v:null)
        echom '[vim-jukit] Failed to create terminal pane'
        return 0
    endif

    let session.output_pane_id = pane_id
    let session.output_visible = 1
    let session.output_float = g:jukit_output_float
    call s:wait_for_pane('output', 8, 50)
    return 1
endfun

" Tri-state term entry point. term mode shares the output slot with
" splits#output (a session can be filled either by output or term, not
" both), so the visibility flags are the same. The "no session" branch
" is async because it needs the floating-input dialog.
fun! jukit#zellij#splits#term(...) abort
    let g:_jukit_python = 0
    call jukit#zellij#splits#_session_init()
    let session = jukit#zellij#splits#_active_session()

    if type(session) == type(v:null)
        let default_name = jukit#util#get_unique_id()
        call jukit#util#prompt_session_name(default_name,
            \ function('s:after_term_session_name'))
        return
    endif

    if session.output_visible == -1
        call jukit#zellij#splits#_create_term_pane()
        return
    endif

    if session.output_visible == 1
        call jukit#zellij#splits#hide_output()
        return
    endif

    if session.output_visible == 0
        call jukit#zellij#splits#show_output()
        return
    endif
endfun

" Continuation for splits#term's "no active session" branch.
fun! s:after_term_session_name(name) abort
    if empty(a:name)
        echom '[vim-jukit] session creation cancelled'
        return
    endif
    call jukit#zellij#splits#_create_session(a:name)
    call jukit#zellij#splits#_create_term_pane()
endfun

" Page-scroll the active session's output pane up or down. Bound to
" <leader>j / <leader>k. Originally these scrolled the (deleted)
" outhist pane; the function name is kept for keybinding-call-site
" stability.
fun! jukit#zellij#splits#out_hist_scroll(down) abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || empty(session.output_pane_id)
        return
    endif
    if a:down
        call jukit#zellij#cmd#zellij_command(
            \ 'page-scroll-down', '--pane-id', session.output_pane_id)
    else
        call jukit#zellij#cmd#zellij_command(
            \ 'page-scroll-up', '--pane-id', session.output_pane_id)
    endif
endfun

" If the active session has no output pane left, drop it entirely.
" The next <leader>os / <leader>tt then sees no active session and
" re-prompts for a name -- which is what users expect after explicitly
" closing the pane (vs. the previous behavior where the empty session
" would silently linger and short-circuit the prompt).
fun! jukit#zellij#splits#_delete_active_session_if_empty() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null)
        return
    endif
    if !empty(session.output_pane_id)
        return
    endif
    call remove(b:jukit_sessions, b:jukit_active_session)
    let b:jukit_active_session = -1
    unlet! g:jukit_output_title
    call jukit#zellij#splits#_invalidate_cache()
endfun

fun! jukit#zellij#splits#close_output_split() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) != type(v:null) && !empty(session.output_pane_id)
        call jukit#zellij#cmd#zellij_command(
            \ 'close-pane', '--pane-id', session.output_pane_id)
        let session.output_pane_id = ''
        let session.output_visible = -1
    endif

    unlet! g:jukit_output_title
    call jukit#zellij#splits#_invalidate_cache()
    call jukit#zellij#splits#_delete_active_session_if_empty()
endfun

" QuitPre / BufDelete cleanup. Closes every pane in every session for
" this buffer, not just the active one. Without this, switching between
" sessions during a vim session leaks ipython panes -- the active one
" gets closed but the others linger in zellij after vim exits.
fun! jukit#zellij#splits#cleanup_all_sessions() abort
    if !exists('b:jukit_sessions')
        return
    endif
    for session in b:jukit_sessions
        if !empty(session.output_pane_id)
            call jukit#zellij#cmd#zellij_command(
                \ 'close-pane', '--pane-id', session.output_pane_id)
        endif
    endfor
    let b:jukit_sessions = []
    let b:jukit_active_session = -1
    unlet! g:jukit_output_title
    call jukit#zellij#splits#_invalidate_cache()
endfun

fun! jukit#zellij#splits#exists(...) abort
    " Reality-based: ask zellij which panes currently exist via
    " `list-panes --json`, and check whether our captured pane ids
    " appear there. We match by id rather than by title because zellij
    " updates pane titles to reflect the running command (e.g. once
    " ipython starts, the title changes from "jukit_output_<uid>" to
    " something like "ipython3"), but the pane id is stable.
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null)
        return 0
    endif

    let output_present = !empty(session.output_pane_id)
        \ && jukit#zellij#splits#_pane_with_id_exists(session.output_pane_id)

    " Reconcile the active session's output_visible flag with reality.
    " If the pane the user thought was visible has actually been closed
    " (e.g. manually via `zellij action close-pane` from outside vim),
    " flip its flag to -1 so the next <leader>os creates a fresh pane
    " instead of trying to show / send to a nonexistent one.
    if session.output_visible == 1 && !output_present
        let session.output_visible = -1
        let session.output_pane_id = ''
    endif

    return output_present
endfun
