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
" b:jukit_sessions. A session is just a named pair of (output pane,
" outhist pane), each of which may currently exist or not, and each
" of which may currently be visible or hidden. b:jukit_active_session
" indexes into the list (or is -1 if no session has been created yet).
"
" The "active" session's output_title and outhist_title are mirrored
" to the legacy globals g:jukit_output_title / g:jukit_outhist_title
" so that the cross-backend dispatcher in autoload/jukit/send.vim
" continues to work without modification: it always talks to the
" active session's output pane.
"
" A BufEnter autocmd (S06) re-syncs the globals when the user moves
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

" Set the active session by index and sync the legacy g: globals.
" Pass -1 to clear the active session entirely.
fun! jukit#zellij#splits#_set_active_session(idx) abort
    call jukit#zellij#splits#_session_init()
    let b:jukit_active_session = a:idx
    if a:idx < 0 || a:idx >= len(b:jukit_sessions)
        unlet! g:jukit_output_title
        unlet! g:jukit_outhist_title
        return
    endif
    let session = b:jukit_sessions[a:idx]
    let session.last_used = localtime()
    let g:jukit_output_title = session.output_title
    let g:jukit_outhist_title = session.outhist_title
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
        unlet! g:jukit_outhist_title
        return
    endif
    let session = b:jukit_sessions[b:jukit_active_session]
    let g:jukit_output_title = session.output_title
    let g:jukit_outhist_title = session.outhist_title
endfun

" Create a new session entry with the given user-supplied name. Pane
" titles are derived from the name plus a unique-id suffix so multiple
" sessions can share a display name without colliding in zellij. The
" new session has no panes yet (output_visible / outhist_visible = -1,
" and the *_pane_id fields are empty until cmd#launch returns one).
" Returns the session index. Becomes the active session as a side
" effect.
fun! jukit#zellij#splits#_create_session(name) abort
    call jukit#zellij#splits#_session_init()
    let uid = jukit#util#get_unique_id()
    let session = {
        \ 'name':            a:name,
        \ 'output_title':    'jukit_output_' . uid,
        \ 'output_pane_id':  '',
        \ 'outhist_title':   'jukit_outhist_' . uid,
        \ 'outhist_pane_id': '',
        \ 'output_visible':  -1,
        \ 'outhist_visible': -1,
        \ 'last_used':       localtime(),
        \ }
    call add(b:jukit_sessions, session)
    let idx = len(b:jukit_sessions) - 1
    call jukit#zellij#splits#_set_active_session(idx)
    return idx
endfun

" =====================================================================
" Hide / show wrappers for the active session.
"
" These are thin glue between the session model (which carries
" output_visible / outhist_visible flags) and the cmd.vim primitives
" (which know how to actually flip pane visibility in zellij). Each
" wrapper updates the session dict's flag after the cmd succeeds.
"
" The functions are no-ops if there's no active session or the
" relevant pane doesn't exist.
" =====================================================================

fun! jukit#zellij#splits#hide_output() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || session.output_visible != 1
        return
    endif
    call jukit#zellij#cmd#hide_pane_by_id(
        \ session.output_pane_id, g:jukit_output_float)
    let session.output_visible = 0
    call jukit#zellij#splits#_invalidate_cache()
endfun

fun! jukit#zellij#splits#show_output() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || session.output_visible != 0
        return
    endif
    call jukit#zellij#cmd#show_pane_by_id(
        \ session.output_pane_id, g:jukit_output_float)
    let session.output_visible = 1
    call jukit#zellij#splits#_invalidate_cache()
endfun

fun! jukit#zellij#splits#hide_outhist() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || session.outhist_visible != 1
        return
    endif
    call jukit#zellij#cmd#hide_pane_by_id(
        \ session.outhist_pane_id, g:jukit_outhist_float)
    let session.outhist_visible = 0
    call jukit#zellij#splits#_invalidate_cache()
endfun

fun! jukit#zellij#splits#show_outhist() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || session.outhist_visible != 0
        return
    endif
    call jukit#zellij#cmd#show_pane_by_id(
        \ session.outhist_pane_id, g:jukit_outhist_float)
    let session.outhist_visible = 1
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
" shown too (creating it if needed). Same for outhist.
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

    let pick = jukit#util#select_session(items)
    if pick < 0
        return
    endif

    " Snapshot what was visible in the OLD active session, so we can
    " restore the same shape in the NEW active session after the switch.
    let old = jukit#zellij#splits#_active_session()
    let want_output = type(old) != type(v:null) && old.output_visible == 1
    let want_outhist = type(old) != type(v:null) && old.outhist_visible == 1

    " "Create new..." sentinel is the last entry.
    if pick == len(items) - 1
        let default_name = jukit#util#get_unique_id()
        let name = jukit#util#prompt_session_name(default_name)
        if empty(name)
            return
        endif
        " Hide whatever the OLD active had visible before switching.
        if want_output
            call jukit#zellij#splits#hide_output()
        endif
        if want_outhist
            call jukit#zellij#splits#hide_outhist()
        endif
        call jukit#zellij#splits#_create_session(name)
        " Don't auto-spawn anything; the user can <leader>os / <leader>hs
        " to fill the new session.
        return
    endif

    " Existing session selected. Map the picker index back to the real
    " b:jukit_sessions index via the sorted order.
    let new_idx = order[pick]
    if new_idx == b:jukit_active_session
        " No-op: user picked the already-active session.
        return
    endif

    " Hide the OLD session's visible panes.
    if want_output
        call jukit#zellij#splits#hide_output()
    endif
    if want_outhist
        call jukit#zellij#splits#hide_outhist()
    endif

    call jukit#zellij#splits#_set_active_session(new_idx)

    " Mirror the OLD session's visibility into the NEW session. If the
    " NEW session has the corresponding pane already, just unhide it.
    " If it doesn't have one yet, create it now so the swap actually
    " produces visible state for the user.
    if want_output
        let s = jukit#zellij#splits#_active_session()
        if s.output_visible == 0
            call jukit#zellij#splits#show_output()
        elseif s.output_visible == -1
            call jukit#zellij#splits#_create_output_pane()
        endif
    endif
    if want_outhist
        let s = jukit#zellij#splits#_active_session()
        if s.outhist_visible == 0
            call jukit#zellij#splits#show_outhist()
        elseif s.outhist_visible == -1
            call jukit#zellij#splits#_create_outhist_pane()
        endif
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
fun! jukit#zellij#splits#output(...) abort
    call jukit#zellij#splits#_session_init()
    let session = jukit#zellij#splits#_active_session()

    " Branch 1: no active session at all -- prompt and create.
    if type(session) == type(v:null)
        let default_name = jukit#util#get_unique_id()
        let name = jukit#util#prompt_session_name(default_name)
        if empty(name)
            echom '[vim-jukit] session creation cancelled'
            return
        endif
        call jukit#zellij#splits#_create_session(name)
        call call('jukit#zellij#splits#_create_output_pane', a:000)
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
    call s:wait_for_pane('output', 8, 50)
    return 1
endfun

" Tri-state term entry point. term mode shares the output slot with
" splits#output (a session can be filled either by output or term, not
" both), so the visibility flags are the same.
fun! jukit#zellij#splits#term(...) abort
    let g:_jukit_python = 0
    call jukit#zellij#splits#_session_init()
    let session = jukit#zellij#splits#_active_session()

    if type(session) == type(v:null)
        let default_name = jukit#util#get_unique_id()
        let name = jukit#util#prompt_session_name(default_name)
        if empty(name)
            echom '[vim-jukit] session creation cancelled'
            return
        endif
        call jukit#zellij#splits#_create_session(name)
        call jukit#zellij#splits#_create_term_pane()
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

" Internal: actually create the outhist pane for the active session.
" Spawns the slim viewer directly in the new pane (--cmd_args), captures
" the new pane's id from cmd#launch, updates the session dict.
fun! jukit#zellij#splits#_create_outhist_pane() abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null)
        echom '[vim-jukit] _create_outhist_pane called with no active session'
        return 0
    endif

    " The history pane is created relative to the output pane (so the
    " configured outhist_direction is interpreted from output's position,
    " not vim's). Focus output by id first if it's currently visible.
    if session.output_visible == 1 && !empty(session.output_pane_id)
        call jukit#zellij#cmd#focus_pane_by_id(session.output_pane_id)
    endif

    let g:jukit_outhist_title = session.outhist_title
    call jukit#zellij#splits#_invalidate_cache()

    " Spawn the slim outhist viewer directly in the new pane (no shell, no
    " ipython, no _build_shell_cmd indirection). The viewer reads commands
    " from stdin via subsequent zellij action write-chars calls; see
    " helpers/jukit_outhist_view.py for the protocol.
    let viewer = jukit#util#plugin_path() . g:_jukit_ps . 'helpers'
        \ . g:_jukit_ps . 'jukit_outhist_view.py'
    let outhist_json = expand('%:p:h') . g:_jukit_ps . '.jukit'
        \ . g:_jukit_ps . expand('%:t:r') . '_outhist.json'
    let cmd_args = ['python3', viewer, outhist_json,
        \ '--max-width-factor', string(g:jukit_sixelcat_width_factor)]

    let pane_id = jukit#zellij#cmd#launch(
        \ g:jukit_zellij_outhist_direction,
        \ session.outhist_title,
        \ cmd_args,
        \ g:jukit_outhist_float)

    if type(pane_id) == type(v:null)
        echom '[vim-jukit] Failed to create history pane'
        call jukit#zellij#cmd#focus_vim()
        return 0
    endif

    let session.outhist_pane_id = pane_id
    let session.outhist_visible = 1
    call s:wait_for_pane('outhist', 8, 50)
    return 1
endfun

" Tri-state outhist entry point. Same shape as splits#output: the active
" session's outhist_visible flag drives the branch.
fun! jukit#zellij#splits#history(...) abort
    if g:jukit_auto_output_hist
        call jukit#splits#toggle_auto_hist(1)
    endif

    call jukit#zellij#splits#_session_init()
    let session = jukit#zellij#splits#_active_session()

    " Branch 1: no active session -- prompt for one.
    if type(session) == type(v:null)
        let default_name = jukit#util#get_unique_id()
        let name = jukit#util#prompt_session_name(default_name)
        if empty(name)
            echom '[vim-jukit] session creation cancelled'
            return
        endif
        call jukit#zellij#splits#_create_session(name)
        call jukit#zellij#splits#_create_outhist_pane()
        return
    endif

    " Branch 2: active session, no outhist pane yet -- create.
    if session.outhist_visible == -1
        call jukit#zellij#splits#_create_outhist_pane()
        return
    endif

    " Branch 3: outhist visible -- hide.
    if session.outhist_visible == 1
        call jukit#zellij#splits#hide_outhist()
        return
    endif

    " Branch 4: outhist hidden -- show.
    if session.outhist_visible == 0
        call jukit#zellij#splits#show_outhist()
        return
    endif
endfun

fun! jukit#zellij#splits#_send_viewer_cmd(text) abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || empty(session.outhist_pane_id)
        return
    endif
    let text = substitute(a:text, '\n$\|\r$', '', '')
    call jukit#zellij#cmd#zellij_command(
        \ 'write-chars', '--pane-id', session.outhist_pane_id, text)
    call jukit#zellij#cmd#zellij_command(
        \ 'write', '--pane-id', session.outhist_pane_id, '13')
endfun

fun! jukit#zellij#splits#out_hist_scroll(down) abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || empty(session.outhist_pane_id)
        return
    endif
    if a:down
        call jukit#zellij#cmd#zellij_command(
            \ 'page-scroll-down', '--pane-id', session.outhist_pane_id)
    else
        call jukit#zellij#cmd#zellij_command(
            \ 'page-scroll-up', '--pane-id', session.outhist_pane_id)
    endif
endfun

fun! jukit#zellij#splits#close_history() abort
    call jukit#splits#toggle_auto_hist(0)
    let g:jukit_outhist_last_cell = -1

    let session = jukit#zellij#splits#_active_session()
    if type(session) != type(v:null) && !empty(session.outhist_pane_id)
        " Ask the viewer to exit cleanly first; close-pane below would
        " kill it either way, but a quit gives it a chance to flush
        " stdout / release any temp resources.
        call jukit#zellij#splits#_send_viewer_cmd('quit')
        call jukit#zellij#cmd#zellij_command(
            \ 'close-pane', '--pane-id', session.outhist_pane_id)
        let session.outhist_pane_id = ''
        let session.outhist_visible = -1
    endif

    unlet! g:jukit_outhist_title
    call jukit#zellij#splits#_invalidate_cache()
endfun

fun! jukit#zellij#splits#close_output_split() abort
    if jukit#zellij#splits#exists('outhist')
        call jukit#zellij#splits#close_history()
    endif

    let session = jukit#zellij#splits#_active_session()
    if type(session) != type(v:null) && !empty(session.output_pane_id)
        call jukit#zellij#cmd#zellij_command(
            \ 'close-pane', '--pane-id', session.output_pane_id)
        let session.output_pane_id = ''
        let session.output_visible = -1
    endif

    unlet! g:jukit_output_title
    call jukit#zellij#splits#_invalidate_cache()
endfun

fun! jukit#zellij#splits#show_last_cell_output(force) abort
    call jukit#util#md_buffer_vars()

    if !jukit#zellij#splits#exists('outhist')
        return
    elseif !exists('g:jukit_outhist_last_cell')
        let g:jukit_outhist_last_cell = -1
    endif

    let cell_id = jukit#util#get_current_cell_id()

    if cell_id == g:jukit_outhist_last_cell && !a:force
        return
    endif

    let g:jukit_outhist_last_cell = cell_id

    " The viewer's protocol is line-based: `cell <id>` for code cells,
    " `cell <id> md` for markdown cells. The viewer re-reads the outhist
    " json on every cell command, so it picks up new outputs from
    " in-flight cell executions in the output pane without any extra
    " state coordination.
    let md_suffix = jukit#util#is_md_cell(cell_id) ? ' md' : ''
    call jukit#zellij#splits#_send_viewer_cmd('cell ' . cell_id . md_suffix)
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
    let outhist_present = !empty(session.outhist_pane_id)
        \ && jukit#zellij#splits#_pane_with_id_exists(session.outhist_pane_id)

    " Reconcile the active session's visibility flags with reality. If a
    " pane the user thought was visible has actually been closed (e.g.
    " manually via `zellij action close-pane` from outside vim), flip
    " its flag to -1 so the next <leader>os / <leader>hs creates a fresh
    " pane instead of trying to show / send to a nonexistent one.
    "
    " We only reconcile the visible-1 case because hidden panes might
    " or might not appear in list-panes depending on the float-layer
    " state, and we don't want to spuriously demote a hidden-but-still-
    " alive pane to -1.
    if session.output_visible == 1 && !output_present
        let session.output_visible = -1
        let session.output_pane_id = ''
    endif
    if session.outhist_visible == 1 && !outhist_present
        let session.outhist_visible = -1
        let session.outhist_pane_id = ''
    endif

    if a:0 > 0 && a:1 ==# 'output'
        return output_present
    elseif a:0 > 0 && a:1 ==# 'outhist'
        return outhist_present
    else
        return output_present && outhist_present
    endif
endfun
