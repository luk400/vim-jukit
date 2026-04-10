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
" Lazy-initialize b:jukit_sessions for the current buffer. Idempotent.
" Also kicks off the lazy-load-from-disk path so persisted sessions
" from a prior nvim run are restored as soon as anything touches the
" session model.
fun! jukit#zellij#splits#_session_init() abort
    call jukit#zellij#splits#_lazy_load_state()
    if !exists('b:jukit_sessions')
        let b:jukit_sessions = []
    endif
    if !exists('b:jukit_active_session')
        let b:jukit_active_session = -1
    endif
endfun

" =====================================================================
" Cross-restart session persistence (zellij only).
"
" Sessions are saved to .jukit/<py_basename>_zellij_sessions.json on
" every meaningful state change (create, attach, close, kill). When
" nvim is closed and re-opened against the same .py file, the BufEnter
" hook (-> _sync_globals_from_buffer -> _lazy_load_state) reads the
" file, validates that the recorded zellij pane ids still exist in
" the current zellij session, and rebuilds b:jukit_sessions. Stale
" entries (closed panes, different zellij session) are dropped.
"
" The persistence file format:
"
"   {
"     "zellij_session":      "<value of $ZELLIJ at save time>",
"     "active_session_name": "<name>",
"     "sessions": [
"       {
"         "name":            "<user-supplied name>",
"         "output_title":    "jukit_output_<uid>",
"         "output_pane_id":  "terminal_<n>",
"         "output_float":    0|1,
"         "last_used":       <int>
"       },
"       ...
"     ]
"   }
"
" The zellij_session field is the gating check for staleness: if the
" current $ZELLIJ doesn't match what was saved, the pane ids belong
" to a different (now-gone) zellij instance and reconnect can't work.
" In that case the file is ignored (not deleted -- the user might
" re-attach to the original zellij session later).
" =====================================================================

" Path to the persistence file for the current buffer's .py file.
" Returns '' for non-file buffers.
fun! jukit#zellij#splits#_persist_path() abort
    let py_dir = expand('%:p:h')
    let py_basename = expand('%:p:t:r')
    if empty(py_basename) || empty(py_dir) || !empty(&buftype)
        return ''
    endif
    let jukit_dir = py_dir . g:_jukit_ps . '.jukit' . g:_jukit_ps
    return jukit_dir . py_basename . '_zellij_sessions.json'
endfun

" Persist the current b:jukit_sessions list to disk. Called from each
" mutating entry point (_create_session, _create_output_pane,
" _create_term_pane, close_output_split, _delete_active_session_if_empty,
" _kill_all_sessions) and from the QuitPre/BufDelete autocmd. Idempotent
" -- saving an unchanged state just rewrites the file with the same
" content. When the session list is empty, the on-disk file is deleted
" so the next load doesn't see ghost entries.
fun! jukit#zellij#splits#_persist_state() abort
    let path = jukit#zellij#splits#_persist_path()
    if empty(path)
        return
    endif

    if !exists('b:jukit_sessions') || empty(b:jukit_sessions)
        if filereadable(path)
            call delete(path)
        endif
        return
    endif

    let dir = fnamemodify(path, ':h')
    if !isdirectory(dir)
        call mkdir(dir, 'p')
    endif

    " Persist output_visible too: it's the user's intent at save time
    " (visible vs. hidden vs. uninitialized) and the most likely state
    " on next load. There's an edge case where a `zellij action`
    " between save and load changes the actual pane state -- the load
    " path will then have a stale flag, and the user's first
    " <leader>os may toggle the wrong way. Acceptable; the user can
    " hit it again to recover.
    let sessions_to_save = copy(b:jukit_sessions)

    let active_name = ''
    if b:jukit_active_session >= 0
        \ && b:jukit_active_session < len(b:jukit_sessions)
        let active_name = b:jukit_sessions[b:jukit_active_session].name
    endif

    let data = {
        \ 'zellij_session':      $ZELLIJ,
        \ 'active_session_name': active_name,
        \ 'sessions':            sessions_to_save,
        \ }

    call writefile([json_encode(data)], path, 'b')
endfun

" Lazy-load persisted sessions for the current buffer. No-op if state
" has already been loaded for this buffer (`b:jukit_sessions_loaded`),
" or if the file isn't readable, or if the saved zellij_session doesn't
" match the current $ZELLIJ. Validates each persisted session against
" `list-panes --json` and drops entries whose panes are gone.
fun! jukit#zellij#splits#_lazy_load_state() abort
    if exists('b:jukit_sessions_loaded') && b:jukit_sessions_loaded
        return
    endif

    let path = jukit#zellij#splits#_persist_path()
    if empty(path)
        return
    endif
    " Even if the load fails or finds nothing, set the flag so we
    " don't repeatedly hit the disk on every BufEnter.
    let b:jukit_sessions_loaded = 1

    if !filereadable(path)
        return
    endif

    let content = join(readfile(path), "\n")
    if empty(content)
        return
    endif
    try
        let data = json_decode(content)
    catch
        echom '[vim-jukit] Failed to parse session persistence: ' . v:exception
        return
    endtry

    if type(data) != type({}) || !has_key(data, 'sessions')
        return
    endif

    " Stale check: a different zellij session means the pane ids are
    " from a no-longer-running instance. Don't reconnect.
    if get(data, 'zellij_session', '') !=# $ZELLIJ
        return
    endif

    " Validate each session's pane id. Sessions whose panes have been
    " manually closed (zellij action close-pane) are silently dropped.
    " Sessions that never had a pane (e.g. allocated via switch_session
    " "Create new..." but never <leader>os'd) are kept with
    " output_visible reset to -1 so the user can <leader>os into them.
    let valid = []
    for sess in data.sessions
        if !has_key(sess, 'output_pane_id') || empty(sess.output_pane_id)
            let sess.output_visible = -1
            call add(valid, sess)
            continue
        endif
        if jukit#zellij#splits#_pane_with_id_exists(sess.output_pane_id)
            " Pane is alive. Trust the persisted output_visible flag
            " (it's the user's intent at save time, and the panes
            " usually still match it on next attach). Default to 1
            " (visible) for old persistence files that pre-date
            " visibility persistence.
            if !has_key(sess, 'output_visible') || sess.output_visible == -1
                let sess.output_visible = 1
            endif
            call add(valid, sess)
        endif
    endfor

    if empty(valid)
        return
    endif

    let b:jukit_sessions = valid

    " Restore active session: prefer the explicit active_session_name
    " field; fall back to the first surviving entry if the recorded
    " active session was dropped.
    let active_name = get(data, 'active_session_name', '')
    let active_idx = -1
    if !empty(active_name)
        for i in range(len(valid))
            if valid[i].name ==# active_name
                let active_idx = i
                break
            endif
        endfor
    endif
    if active_idx < 0
        let active_idx = 0
    endif
    let b:jukit_active_session = active_idx
    let g:jukit_output_title = valid[active_idx].output_title
    call jukit#zellij#splits#_invalidate_cache()

    echom '[vim-jukit] Restored ' . len(valid) . ' session(s) from disk.'
endfun

" Return 1 iff a session with the given name already exists in this
" buffer. Used by the create-new prompt path to reject duplicate names
" (the user has to pick a unique name now -- we no longer auto-generate
" a UID for them).
fun! s:session_name_exists(name) abort
    if !exists('b:jukit_sessions')
        return 0
    endif
    for sess in b:jukit_sessions
        if sess.name ==# a:name
            return 1
        endif
    endfor
    return 0
endfun

" Charset validation for session names. The session name goes directly
" into the per-session outhist filename
" (<basename>_<session>_outhist.json), into IPython magic args, and is
" displayed in the picker, so we restrict it to a known-safe character
" set. Returns 1 if valid.
fun! s:session_name_valid(name) abort
    return a:name =~# '^[A-Za-z0-9_-]\+$'
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
    " Persist the active-session change so that the next nvim run
    " restores the same active session, not just the same set of
    " sessions.
    call jukit#zellij#splits#_persist_state()
    let g:jukit_output_title = session.output_title
    call jukit#zellij#splits#_invalidate_cache()
endfun

" Re-sync the legacy globals from this buffer's active session. Called
" from a BufEnter autocmd (see plugin/jukit.vim) so that switching
" between buffers automatically points the cross-backend dispatcher at
" the right pane. Also opportunistically lazy-loads persisted state on
" the FIRST BufEnter for a buffer, so reopening a previously-touched
" .py file silently rebuilds b:jukit_sessions from .jukit/<py>_zellij_sessions.json
" (provided the recorded zellij_session matches and the panes still
" exist). No-op for non-file buffers and for buffers that have already
" been initialized.
fun! jukit#zellij#splits#_sync_globals_from_buffer() abort
    call jukit#zellij#splits#_lazy_load_state()
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
    call jukit#zellij#splits#_persist_state()
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
    " optionally a "Load previous..." sentinel, "Create new...", and
    " optionally a "Kill all sessions" sentinel.
    let n = len(b:jukit_sessions)
    let order = range(n)
    call sort(order, {a, b -> b:jukit_sessions[b].last_used - b:jukit_sessions[a].last_used})
    let items = []
    for idx in order
        let s = b:jukit_sessions[idx]
        let marker = (idx == b:jukit_active_session) ? ' (active)' : ''
        call add(items, s.name . marker)
    endfor

    " Loadable = saved on disk MINUS sessions already in b:jukit_sessions.
    " Computed up front so the picker only shows the "Load previous..."
    " entry when there's actually something behind it -- otherwise the
    " entry would be a dead end on first-time use of a new file.
    let saved = jukit#util#list_saved_sessions()
    let loadable = filter(copy(saved), {_, name -> !s:session_name_exists(name)})
    let load_idx = -1
    if !empty(loadable)
        let load_idx = len(items)
        call add(items, 'Load previous...')
    endif

    " "Kill session...": opens a sub-picker listing active + archived
    " sessions. Only shown when there's at least one active session or
    " at least one archived session on disk.
    let kill_idx = -1
    let archived = filter(copy(saved), {_, name -> !s:session_name_exists(name)})
    if n > 0 || !empty(archived)
        let kill_idx = len(items)
        call add(items, 'Kill session...')
    endif

    let create_idx = len(items)
    call add(items, 'Create new...')

    " Snapshot what was visible in the OLD active session BEFORE the
    " picker pops, so we can mirror the same shape into whatever the
    " user lands on. We have to capture this now (in a closure-like
    " dict) because the floating dialog is async and the active session
    " could in principle change between dialog open and dialog submit.
    let old = jukit#zellij#splits#_active_session()
    let snap = {
        \ 'order':        order,
        \ 'load_idx':     load_idx,
        \ 'create_idx':   create_idx,
        \ 'kill_idx':     kill_idx,
        \ 'loadable':     loadable,
        \ 'archived':     archived,
        \ 'want_output':  type(old) != type(v:null) && old.output_visible == 1,
        \ }

    call jukit#util#select_session(items,
        \ {pick -> s:after_switch_pick(pick, snap)})
endfun

" Continuation: the user picked an entry in the session picker (or
" cancelled). Branches into 'create new', 'load previous', or 'switch
" to existing'.
fun! s:after_switch_pick(pick, snap) abort
    if a:pick < 0
        return
    endif

    " "Create new..." sentinel.
    if a:pick == a:snap.create_idx
        " Empty default: the user must explicitly name new sessions.
        " Empty submission == cancellation (handled in the continuation).
        " Re-bind a:snap into a plain local so the lambda below
        " captures it via the standard local-variable closure path
        " (vimscript closures don't reliably reach into enclosing a:).
        let snap = a:snap
        call jukit#util#prompt_session_name('',
            \ {n -> s:after_switch_create_new(n, snap)})
        return
    endif

    " "Load previous..." sentinel: open a second floating select with
    " the loadable session names. Only present when load_idx >= 0.
    if a:snap.load_idx >= 0 && a:pick == a:snap.load_idx
        let snap = a:snap
        call jukit#util#floating_select(
            \ {'items': a:snap.loadable,
            \  'title': 'Load Previous Session'},
            \ {idx -> s:after_switch_load_previous(idx, snap)})
        return
    endif

    " "Kill session..." sentinel: open a sub-picker listing individual
    " sessions (active + archived) and "Kill all sessions" at the bottom.
    if a:snap.kill_idx >= 0 && a:pick == a:snap.kill_idx
        call s:open_kill_session_picker(a:snap)
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

" Continuation: the user picked a previously-saved session from the
" "Load previous..." dialog. Allocates a new in-buffer session entry
" with the same NAME as the saved one, which causes %jukit_init's
" --session=<name> path to point the new ipython process at the
" already-existing per-session outhist file. From the user's POV the
" old session is "resurrected": <leader>so on cells with saved output
" works immediately, and re-running cells overwrites only the cells
" that get re-run.
fun! s:after_switch_load_previous(idx, snap) abort
    if a:idx < 0
        return
    endif
    if a:idx >= len(a:snap.loadable)
        return
    endif
    let name = a:snap.loadable[a:idx]

    " Re-check at submit time, in case the picker open / submit window
    " was long enough for the user to load this session via another path.
    if s:session_name_exists(name)
        echom '[vim-jukit] Session "' . name . '" already loaded.'
        return
    endif

    if a:snap.want_output
        call jukit#zellij#splits#hide_output()
    endif

    call jukit#zellij#splits#_create_session(name)

    if a:snap.want_output
        call jukit#zellij#splits#_create_output_pane()
    endif

    echom '[vim-jukit] Loaded previous session "' . name . '". '
        \. 'Use <leader>so to display saved outputs; re-run cells to update them.'
endfun

" Continuation: the user picked "Create new..." and supplied a name
" for the brand new session. Hide whatever the OLD active had visible,
" allocate the new session, and immediately auto-spawn an output pane
" if the OLD active had one -- the user expects an instantly-usable
" session, not one they have to <leader>os into manually right after
" creation (Y03).
fun! s:after_switch_create_new(name, snap) abort
    if empty(a:name)
        echom '[vim-jukit] session creation cancelled'
        return
    endif
    if !s:session_name_valid(a:name)
        echom '[vim-jukit] Session name "' . a:name . '" is invalid. '
            \. 'Use only A-Z, a-z, 0-9, _ and -.'
        let snap = a:snap
        call jukit#util#prompt_session_name('',
            \ {n -> s:after_switch_create_new(n, snap)},
            \ 'Session Name (invalid chars)')
        return
    endif
    if s:session_name_exists(a:name)
        echom '[vim-jukit] Session "' . a:name . '" already exists in this '
            \. 'buffer. Please choose a different name.'
        let snap = a:snap
        call jukit#util#prompt_session_name('',
            \ {n -> s:after_switch_create_new(n, snap)},
            \ 'Session Name (in use)')
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
    call jukit#zellij#splits#_persist_state()
    call s:wait_for_pane('output', 8, 50)

    if a:0 > 0
        call jukit#zellij#cmd#send_text('output', a:1)
    endif

    if !g:jukit_inline_plotting && !g:jukit_save_output
        call jukit#zellij#cmd#send_text('output', g:jukit_shell_cmd)
        return 1
    endif

    call jukit#zellij#cmd#send_text('output', jukit#splits#_build_shell_cmd())
    " Also publish the current sixelcat width factor so the python side
    " can re-read it at runtime (cat.py::_read_runtime_factor). Writing
    " it here means ``:let g:jukit_sixelcat_width_factor = X`` followed
    " by ``:call jukit#util#ipython_info_write({'sixelcat_width_factor':
    " g:jukit_sixelcat_width_factor})`` takes effect on the next render
    " without a pane restart.
    "
    " ``sixelcat_pane_id`` is the bare integer form of the output
    " pane's id (session.output_pane_id is stored as "terminal_<n>";
    " we strip the prefix). cat.py::_query_zellij_pane_dims reads it
    " to filter the ``zellij action list-panes --json`` output down to
    " our specific pane, which is how the python side gets an
    " authoritative "is this pane currently tiled or has it been
    " toggled to hidden-floating" signal -- the pty winsize alone
    " can't distinguish those states.
    let l:sixel_pane_id_int = str2nr(matchstr(session.output_pane_id, '\d\+'))
    call jukit#util#ipython_info_write({
        \ 'terminal': 'zellij',
        \ 'import_complete': 0,
        \ 'sixelcat_width_factor': g:jukit_sixelcat_width_factor,
        \ 'sixelcat_pane_id': l:sixel_pane_id_int,
        \ })
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
    " create the session + output pane in the continuation. Empty default
    " forces the user to pick an explicit name.
    if type(session) == type(v:null)
        let extra_args = a:000
        call jukit#util#prompt_session_name('',
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
    if !s:session_name_valid(a:name)
        echom '[vim-jukit] Session name "' . a:name . '" is invalid. '
            \. 'Use only A-Z, a-z, 0-9, _ and -.'
        let extra_args = a:extra_args
        call jukit#util#prompt_session_name('',
            \ {n -> s:after_output_session_name(n, extra_args)},
            \ 'Session Name (invalid chars)')
        return
    endif
    if s:session_name_exists(a:name)
        echom '[vim-jukit] Session "' . a:name . '" already exists in this '
            \. 'buffer. Please choose a different name.'
        let extra_args = a:extra_args
        call jukit#util#prompt_session_name('',
            \ {n -> s:after_output_session_name(n, extra_args)},
            \ 'Session Name (in use)')
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
    call jukit#zellij#splits#_persist_state()
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
        call jukit#util#prompt_session_name('',
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
    if !s:session_name_valid(a:name)
        echom '[vim-jukit] Session name "' . a:name . '" is invalid. '
            \. 'Use only A-Z, a-z, 0-9, _ and -.'
        call jukit#util#prompt_session_name('',
            \ function('s:after_term_session_name'),
            \ 'Session Name (invalid chars)')
        return
    endif
    if s:session_name_exists(a:name)
        echom '[vim-jukit] Session "' . a:name . '" already exists in this '
            \. 'buffer. Please choose a different name.'
        call jukit#util#prompt_session_name('',
            \ function('s:after_term_session_name'),
            \ 'Session Name (in use)')
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
    call jukit#zellij#splits#_persist_state()
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
    call jukit#zellij#splits#_persist_state()
    call jukit#zellij#splits#_invalidate_cache()
    call jukit#zellij#splits#_delete_active_session_if_empty()
endfun

" Persist sessions on QuitPre/BufDelete instead of closing the panes.
" This is the cross-restart persistence pivot: prior to 2026-04 the
" autocmd-installed handler closed every pane to avoid leaks, but the
" new model is "let panes outlive nvim and reconnect on next open".
" The kill path now lives in jukit#zellij#splits#_kill_all_sessions
" (and its user-facing wrapper kill_all_sessions_with_confirm), which
" the <leader>ss "Kill session..." picker entry routes through.
fun! jukit#zellij#splits#cleanup_all_sessions() abort
    " Backwards-compat shim: the old autocmd handler name. Now just
    " persists; doesn't kill panes. Kept under the old name so any
    " plugin/jukit.vim that hasn't been updated still does something
    " reasonable rather than blowing up.
    call jukit#zellij#splits#_persist_state()
endfun

" Close every pane in every session for this buffer and clear local
" state. Used by the explicit "Kill all sessions" picker entry, which
" wraps it in a yes/no confirmation dialog. Persists the now-empty
" state at the end so the on-disk file is removed.
fun! jukit#zellij#splits#_kill_all_sessions() abort
    if !exists('b:jukit_sessions')
        return
    endif
    for session in b:jukit_sessions
        if !empty(session.output_pane_id)
            call jukit#zellij#cmd#zellij_command(
                \ 'close-pane', '--pane-id', session.output_pane_id)
        endif
        " Delete the per-session outhist file.
        let outhist = jukit#util#session_outhist_path(session.name)
        if !empty(outhist) && filereadable(outhist)
            call delete(outhist)
        endif
    endfor
    " Also delete archived (on-disk-only) outhist files.
    for aname in jukit#util#list_saved_sessions()
        let outhist = jukit#util#session_outhist_path(aname)
        if !empty(outhist) && filereadable(outhist)
            call delete(outhist)
        endif
    endfor
    let b:jukit_sessions = []
    let b:jukit_active_session = -1
    call jukit#zellij#splits#_persist_state()
endfun

" Open the "Kill session..." sub-picker. Lists active sessions, then
" archived (on-disk-only) sessions marked with " (archived)", then
" "Kill all sessions" at the very bottom.
fun! s:open_kill_session_picker(snap) abort
    let items = []
    let kill_map = []

    " Active sessions.
    for i in range(len(b:jukit_sessions))
        let s = b:jukit_sessions[i]
        let marker = (i == b:jukit_active_session) ? ' (active)' : ''
        call add(items, s.name . marker)
        call add(kill_map, {'type': 'active', 'idx': i, 'name': s.name})
    endfor

    " Archived sessions (saved outhist on disk, not loaded in buffer).
    for aname in a:snap.archived
        call add(items, aname . ' (archived)')
        call add(kill_map, {'type': 'archived', 'idx': -1, 'name': aname})
    endfor

    " "Kill all sessions" at the bottom.
    let kill_all_idx = len(items)
    call add(items, 'Kill all sessions')

    let ctx = {'kill_map': kill_map, 'kill_all_idx': kill_all_idx}
    call jukit#util#floating_select(
        \ {'items': items, 'title': 'Kill Session'},
        \ {pick -> s:after_kill_pick(pick, ctx)})
endfun

" Continuation: the user picked a session to kill from the sub-picker.
fun! s:after_kill_pick(pick, ctx) abort
    if a:pick < 0
        return
    endif

    " "Kill all sessions" at the bottom.
    if a:pick == a:ctx.kill_all_idx
        call jukit#zellij#splits#kill_all_sessions_with_confirm()
        return
    endif

    if a:pick >= len(a:ctx.kill_map)
        return
    endif

    let entry = a:ctx.kill_map[a:pick]

    if entry.type ==# 'active'
        call s:kill_single_active_session(entry.idx)
    elseif entry.type ==# 'archived'
        call s:kill_archived_session(entry.name)
    endif
endfun

" Kill a single active session: close its zellij pane, delete its
" outhist file, remove it from b:jukit_sessions, and persist.
fun! s:kill_single_active_session(idx) abort
    if a:idx < 0 || a:idx >= len(b:jukit_sessions)
        return
    endif
    let session = b:jukit_sessions[a:idx]
    let name = session.name

    " Close the zellij pane if it exists.
    if !empty(session.output_pane_id)
        call jukit#zellij#cmd#zellij_command(
            \ 'close-pane', '--pane-id', session.output_pane_id)
    endif

    " Delete the per-session outhist file.
    let outhist = jukit#util#session_outhist_path(name)
    if !empty(outhist) && filereadable(outhist)
        call delete(outhist)
    endif

    " Remove from the session list.
    call remove(b:jukit_sessions, a:idx)

    " Fix up active_session index.
    if b:jukit_active_session == a:idx
        let b:jukit_active_session = -1
        unlet! g:jukit_output_title
    elseif b:jukit_active_session > a:idx
        let b:jukit_active_session -= 1
    endif

    call jukit#zellij#splits#_invalidate_cache()
    call jukit#zellij#splits#_persist_state()
    echom '[vim-jukit] Killed session "' . name . '".'
endfun

" Kill an archived session: delete its outhist file from disk.
fun! s:kill_archived_session(name) abort
    let outhist = jukit#util#session_outhist_path(a:name)
    if !empty(outhist) && filereadable(outhist)
        call delete(outhist)
        echom '[vim-jukit] Deleted archived session "' . a:name . '" output history.'
    else
        echom '[vim-jukit] No output history found for archived session "' . a:name . '".'
    endif
endfun

" User-facing wrapper around _kill_all_sessions: pops a floating input
" requiring "yes" to confirm before closing the panes. Used by the
" "Kill all sessions" entry in the kill-session sub-picker.
fun! jukit#zellij#splits#kill_all_sessions_with_confirm() abort
    call jukit#util#floating_input(
        \ {'prompt': '[vim-jukit] Type "yes" to kill all sessions: ',
        \  'default': '',
        \  'title': 'Confirm Kill All Sessions'},
        \ function('s:after_kill_confirm'))
endfun

fun! s:after_kill_confirm(reply) abort
    if a:reply !=# 'yes'
        echom '[vim-jukit] kill all cancelled'
        return
    endif
    call jukit#zellij#splits#_kill_all_sessions()
    echom '[vim-jukit] All sessions killed and persistence cleared.'
endfun

" QuitPre handler for zellij. If there are active sessions with panes,
" prompt the user to kill or hide them. Uses vim's synchronous confirm()
" because floating windows can't be shown during QuitPre reliably.
fun! jukit#zellij#splits#on_quit_pre() abort
    if !exists('b:jukit_sessions') || empty(b:jukit_sessions)
        call jukit#zellij#splits#_persist_state()
        return
    endif

    " Count sessions that have a live pane.
    let has_panes = 0
    for session in b:jukit_sessions
        if !empty(session.output_pane_id)
            let has_panes = 1
            break
        endif
    endfor

    if !has_panes
        call jukit#zellij#splits#_persist_state()
        return
    endif

    let choice = confirm(
        \ '[vim-jukit] There are active zellij sessions. What should we do?',
        \ "&Kill sessions\n&Hide sessions\n&Cancel", 2)

    if choice == 1
        " Kill: close all panes, clear state, delete persistence.
        call jukit#zellij#splits#_kill_all_sessions()
    elseif choice == 2
        " Hide: hide visible panes so they don't clutter the layout,
        " but keep them alive for reconnection on next nvim open.
        for session in b:jukit_sessions
            if session.output_visible == 1 && !empty(session.output_pane_id)
                call jukit#zellij#cmd#hide_pane_by_id(
                    \ session.output_pane_id,
                    \ get(session, 'output_float', g:jukit_output_float))
                let session.output_visible = 0
            endif
        endfor
        call jukit#zellij#splits#_persist_state()
    else
        " Cancel: prevent :q by temporarily marking the buffer as
        " modified. Neovim's QuitPre is a notification event, not a
        " veto — neither throw nor echoerr actually stops the quit.
        " Setting &modified makes the subsequent check_changed() in
        " ex_quit fail with E37, which DOES abort the quit. A zero-
        " delay timer clears the flag on the next event loop cycle so
        " the buffer isn't left in a dirty state. :q! bypasses both
        " QuitPre and the modified check, so force-quit always works.
        if !&modified
            let bnr = bufnr('%')
            setlocal modified
            call timer_start(0, {_ -> setbufvar(bnr, '&modified', 0)})
        endif
        return
    endif
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
