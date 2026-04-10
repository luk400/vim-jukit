let s:script_path = expand("<sfile>:p:h")

fun! s:map_extract_ids(v, l) abort
    let id1 = matchstr(a:v, '|%%--%%|.*<\zs.*\ze|.*>')
    let id2 = matchstr(a:v, '|%%--%%|.*<.*|\zs.*\ze>')
    call add(s:ids1, id1)
    call add(s:ids2, id2)
    call add(s:pos, a:l+1)
endfun

fun! jukit#util#catch_load_json(file, ntries_left, time_between) abort
    "in case file is trying to be loaded while it is being written to by
    "another process. if it still can't be loaded after `ntries_left` then
    "it is assumed that it is corrupted and replaced with empty json
    let f_content = readfile(a:file)
    try
        if has('nvim')
            let json = json_decode(f_content)
        else
            let json = json_decode(join(f_content, ''))
        endif
    catch
        echom "[vim-jukit] could not decode json, number of tries left: " . a:ntries_left
        if a:ntries_left > 0
            exe "sleep " . a:time_between . "m"
            let json = jukit#util#catch_load_json(a:file, a:ntries_left - 1, a:time_between)
            let g:ntries = a:ntries_left
        else
            echom "[vim-jukit] json file not readable, replacing with empty json..."
            let json = {}
            call writefile([json_encode(json)], a:file, 'b')
        endif
    endtry

    return json
endfun

fun! jukit#util#get_all_ids() abort
    let lines = getline(1, line('$'))
    let s:ids1 = []
    let s:ids2 = []
    let s:pos = []
    call map(copy(lines), {l, v -> v =~ '|%%--%%|' ? s:map_extract_ids(v, l) : 0})
    return {1: s:ids1, 2: s:ids2, 'pos': s:pos}
endfun

fun! jukit#util#get_unique_id() abort
    let ids = jukit#util#get_all_ids()
    if len(ids[1])
        let existing_ids = [ids[1][0]] + ids[2]
    else
        let existing_ids = []
    endif
python3 << EOF
import random, string, vim

alphabet = string.ascii_uppercase + string.ascii_lowercase + string.digits
existing_ids = vim.eval('existing_ids')

id_exists = True
while id_exists:
    id = ''.join(random.choices(alphabet, k=10))
    id_exists = id in existing_ids

vim.command(f"let id='{id}'")
EOF
    return id
endfun

fun! jukit#util#get_marker_above() abort
    let marker_pos_above = search('|%%--%%|', 'nbW')
    if marker_pos_above
        let id1 = matchstr(getline(marker_pos_above), '|%%--%%|.*<\zs.*\ze|.*>')
        let id2 = matchstr(getline(marker_pos_above), '|%%--%%|.*<.*|\zs.*\ze>')
        let ids = [id1, id2]
    else
        let id_above = -1
        let ids = []
    endif
    return {'ids': ids, 'pos': marker_pos_above}
endfun

fun! jukit#util#get_marker_below() abort
    let marker_pos_below = search('|%%--%%|', 'nW')
    if marker_pos_below
        let id1 = matchstr(getline(marker_pos_below), '|%%--%%|.*<\zs.*\ze|.*>')
        let id2 = matchstr(getline(marker_pos_below), '|%%--%%|.*<.*|\zs.*\ze>')
        let ids = [id1, id2]
    else
        let ids = []
    endif
    return {'ids': ids, 'pos': marker_pos_below}
endfun

fun! jukit#util#get_adjacent_markers() abort
    let ids_below = jukit#util#get_marker_below()
    let ids_above = jukit#util#get_marker_above()
    return {'below': ids_below, 'above': ids_above}
endfun

fun! jukit#util#get_current_cell_id() abort
    let ids = jukit#util#get_adjacent_markers()
    if ids['above']['pos'] != 0
        let cell_id = ids['above']['ids'][1]
    elseif ids['below']['pos'] != 0
        let cell_id = ids['below']['ids'][0]
    else
        let cell_id = 'NONE'
    endif

    return cell_id
endfun

fun! jukit#util#plugin_path() abort
    " Gets absolute path to the vim-jukit/ folder
    let plugin_path = split(s:script_path, g:_jukit_ps)[:-3]
    if g:_jukit_is_windows
        return join(plugin_path, g:_jukit_ps)
    else
        return g:_jukit_ps . join(plugin_path, g:_jukit_ps)
    endif
endfun

let s:last_src_dir = ''

fun! s:resolve_jukit_dir() abort
    " Use the current buffer's directory only when it is a normal file buffer
    " backed by a real path. Otherwise fall back to the most recent valid one
    " seen during this session. Returns '' when no valid dir is known.
    if &buftype ==# '' && !empty(expand('%:p'))
        let s:last_src_dir = expand('%:p:h')
    endif
    if empty(s:last_src_dir)
        return ''
    endif
    return s:last_src_dir . g:_jukit_ps . '.jukit' . g:_jukit_ps
endfun

" Update the sixelcat width factor at runtime.
"
" Sets the vim-side global AND publishes the value to .jukit_info.json
" so the python-side ``cat.py::_read_runtime_factor`` picks it up on
" the next render -- without restarting the IPython pane. Only
" meaningful on the zellij backend (where the sixelcat matplotlib
" backend is wired up); a no-op warning on other backends.
"
" Usage:
"   :call jukit#util#set_sixel_width(0.8)
fun! jukit#util#set_sixel_width(val) abort
    if g:jukit_terminal !=# 'zellij'
        echom '[vim-jukit] set_sixel_width only affects the zellij backend'
        return
    endif
    let g:jukit_sixelcat_width_factor = a:val
    call jukit#util#ipython_info_write({'sixelcat_width_factor': a:val})
endfun

fun! jukit#util#ipython_info_write(dict) abort
    " TODO: is this check necessary?
    if !g:jukit_ipython
        return
    endif

    let dir = s:resolve_jukit_dir()
    if empty(dir)
        return
    endif

    let file = dir . '.jukit_info.json'
    if !isdirectory(dir)
        call mkdir(dir)
    endif

    if !empty(glob(file))
        let json = jukit#util#catch_load_json(file, 5, 500)
    else
        let json = {}
    endif

    call extend(json, a:dict, "force")
    call writefile([json_encode(json)], file, 'b')
endfun

fun! s:get_key(json, key, quiet) abort
    if has_key(a:json, a:key)
        return a:json[a:key]
    elseif !a:quiet
        echom '[vim-jukit] Key "' . a:key . '" not found!'
    endif
    return v:null
endfun

fun! jukit#util#ipython_info_get(keys, ...) abort
    if a:0 > 0
        let quiet = a:1
    else
        let quiet = 0
    endif

    let dir = s:resolve_jukit_dir()
    if empty(dir)
        return v:null
    endif
    let file = dir . '.jukit_info.json'
    if (empty(glob(file)) || !isdirectory(dir)) && !quiet
        echom '[vim-jukit] File ' . file . ' not found!'
        return v:null
    endif

    if !empty(glob(file))
        let json = jukit#util#catch_load_json(file, 5, 500)
    else
        let json = {}
    endif

    if type(a:keys) == 3
        let vals = []
        call map(a:keys, {k,v -> add(vals, s:get_key(json, v, quiet))})
        return vals
    else
        return s:get_key(json, a:keys, quiet)
    endif
endfun

fun! jukit#util#get_visual_selection() abort
    " Credit for this function: 
    " https://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript/6271254#6271254
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return ''
    endif
    let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction

fun! jukit#util#replace_old_markers() abort
    let id_before = jukit#util#get_unique_id()
    fun s:replace() closure
        let new_id = jukit#util#get_unique_id()
        let ids_str =  ' <' . id_before . '|' . new_id . '>'
        let repl = substitute(getline('.'), '|%%--%%|\zs.*\ze', ids_str, 'g')
        call setline(line('.'), repl)
        let id_before = new_id
    endfun

    let id = 1
    let save_view = winsaveview()
    g/|%%--%%|/call s:replace()
    call winrestview(save_view)
endfun

fun! jukit#util#get_terminal() abort
    " Zellij is the only multiplexer-style backend after the 2026-04
    " cleanup; everything else falls through to the in-process
    " vim/nvim terminal.
    if !empty($ZELLIJ)
        return 'zellij'
    elseif has('nvim')
        return 'nvimterm'
    else
        return 'vimterm'
    endif
endfun

fun! jukit#util#get_lang_info() abort
python3 << EOF
import vim, os, sys, json
sys.path.append(vim.eval('jukit#util#plugin_path() . g:_jukit_ps . "helpers"'))
from ipynb_convert import languages

vim.command(f"let json='{json.dumps(languages)}'")
EOF
    let json = json_decode(json)
    if has_key(json, tolower(&ft))
        let ft_json = json[tolower(&ft)]
        let md_start = ft_json['multiline_start'] . g:_jukit_md_mark
        let md_end = g:_jukit_md_mark . ft_json['multiline_end']
        let cchar = ft_json['cchar']
        let ext = ft_json['ext']
        let success = 1
    else
        let md_start = "r\"\"\"" . g:_jukit_md_mark
        let md_end = g:_jukit_md_mark . "\"\"\""
        let cchar = "#"
        let ext = 'py'
        let success = 0
    endif
    return [md_start, md_end, cchar, ext, success]
endfun

fun! jukit#util#md_buffer_vars() abort
    " TODO: this function shouldn't be unnecessarily called so often (even if
    " it doesn't take much time) as it is now, it's ugly. just init the buffer
    " variables in plugin/init.vim instead of everytime a buffer variable is
    " needed! then i can drop the exists() check below
    if exists('b:jukit_md_start')
        return
    endif
    let md_info = jukit#util#get_lang_info()
    let b:jukit_md_start = md_info[0]
    let b:jukit_md_end =  md_info[1]
    let b:jukit_cchar =  md_info[2]
    let b:jukit_md_start_escaped = escape(b:jukit_md_start, '/*')
    let b:jukit_md_end_escaped =  escape(b:jukit_md_end, '/*')
endfun

fun! jukit#util#is_valid_version(vcur, vreq) abort
    " expects lists of length 3 according to semantic versioning convention

    if len(a:vcur)!=3 || len(a:vreq)!=3
        echom '[vim-jukit] invalid version number encountered:'
        echom a:vcur
        echom a:vreq
        return 1 " by default give benefit of the doubt if a version number not in the expected format
    endif

    let valid1 = a:vcur[0] >= a:vreq[0]
    let valid2 = a:vcur[0] > a:vreq[0] || valid1 && a:vcur[1] >= a:vreq[1]
    let valid3 = a:vcur[0] > a:vreq[0] || a:vcur[1] > a:vreq[1] || valid1 && valid2 && a:vcur[2] >= a:vreq[2]

    return (valid1 && valid2 && valid3)
endfun

fun! jukit#util#is_md_cell(cell_id) abort
    let save_view = winsaveview()
    call cursor(line('.')+1, '$')
    let md_cur = search(b:jukit_md_start, 'nbW') > search('|%%--%%| <.*|' . a:cell_id, 'nbW')
    call winrestview(save_view)
    return md_cur
endfun

" Return the raw markdown source lines for the markdown cell enclosing
" the cursor as a single newline-joined string. Caller must verify
" jukit#util#is_md_cell() first and ensure jukit#util#md_buffer_vars()
" was called so b:jukit_md_start_escaped / b:jukit_md_end_escaped exist.
"
" Implementation: bound the inner search to the cell's outer markers
" (returned by get_adjacent_markers, which is what get_current_cell_id
" already trusts) and then scan that bounded range for md_start /
" md_end. This makes the result independent of which line within the
" cell the cursor lands on -- in particular it fixes the case where
" the cursor sits on the closing md_end delimiter or the blank line
" right above it, which used to make the cursor-relative search slide
" off the end and return empty.
"
" The cell_id argument is accepted for API symmetry with is_md_cell()
" but not used inside.
fun! jukit#util#get_md_cell_source(cell_id) abort
    let save_view = winsaveview()
    try
        " get_adjacent_markers reads cursor position; call it BEFORE we
        " move the cursor for the inner searches.
        let markers = jukit#util#get_adjacent_markers()
        let cell_top = markers['above']['pos'] > 0
            \ ? markers['above']['pos'] + 1
            \ : 1
        let cell_bot = markers['below']['pos'] > 0
            \ ? markers['below']['pos'] - 1
            \ : line('$')
        if cell_bot < cell_top
            return ''
        endif

        " Find md_start. Place the cursor at (cell_top, 1) and scan
        " forward with the 'c' flag so a match on cell_top itself is
        " accepted, bounded to cell_bot (inclusive).
        call cursor(cell_top, 1)
        let start_lnum = search(b:jukit_md_start_escaped, 'cW', cell_bot)
        if start_lnum == 0 || start_lnum >= cell_bot
            return ''
        endif

        " Find md_end strictly after md_start, also bounded to cell_bot.
        call cursor(start_lnum + 1, 1)
        let end_lnum = search(b:jukit_md_end_escaped, 'cW', cell_bot)
        if end_lnum == 0 || end_lnum <= start_lnum + 1
            return ''
        endif

        let lines = getline(start_lnum + 1, end_lnum - 1)
        return join(lines, "\n")
    finally
        call winrestview(save_view)
    endtry
endfun

" =====================================================================
" Floating-window dialog helpers (nvim only).
"
" Two callback-based primitives modeled after vibi.nvim's
" prompt_session_name (lua/vibe/session.lua:564) and the create_centered_float
" pattern (lua/vibe/util.lua:6):
"
"   floating_input(opts, Callback)  - single-line text input
"   floating_select(opts, Callback) - vertical menu of items
"
" Both are nvim-only; classic vim falls back to input()/inputlist() so
" call sites stay portable. Both invoke Callback exactly once with the
" result ('' / -1 on cancel) on submit, cancel, or BufLeave.
" =====================================================================

" Single-line floating input. Submits on <CR>, cancels on <Esc>/<C-c>/q
" or when focus leaves the buffer. Calls Callback(name) where name is
" the trimmed input ('' on cancel).
fun! jukit#util#floating_input(opts, Callback) abort
    if !has('nvim')
        call inputsave()
        let name = input(get(a:opts, 'prompt', '[vim-jukit] Input: '),
            \             get(a:opts, 'default', ''))
        call inputrestore()
        call a:Callback(name)
        return
    endif

    let default = get(a:opts, 'default', '')
    let title = ' ' . get(a:opts, 'title', 'Input') . ' '

    let bufnr = nvim_create_buf(v:false, v:true)
    call nvim_buf_set_lines(bufnr, 0, -1, v:false, [default])
    call nvim_set_option_value('bufhidden', 'wipe', {'buf': bufnr})
    call nvim_set_option_value('buflisted', v:false, {'buf': bufnr})

    let width = max([40, strdisplaywidth(default) + 10])
    let width = min([width, &columns - 4])
    let height = 1
    let row = max([0, (&lines - height) / 2])
    let col = max([0, (&columns - width) / 2])

    let winid = nvim_open_win(bufnr, v:true, {
        \ 'relative': 'editor',
        \ 'row': row,
        \ 'col': col,
        \ 'width': width,
        \ 'height': height,
        \ 'style': 'minimal',
        \ 'border': 'rounded',
        \ 'title': title,
        \ 'title_pos': 'center',
        \ 'zindex': 60,
        \ })

    " Stash callback + winid on the buffer so the script-local key handlers
    " can find them after we leave this function.
    let b:_jukit_input_callback = a:Callback
    let b:_jukit_input_winid = winid
    let b:_jukit_input_done = 0

    inoremap <buffer><silent> <CR>  <Esc>:call <SID>floating_input_submit()<CR>
    nnoremap <buffer><silent> <CR>       :call <SID>floating_input_submit()<CR>
    nnoremap <buffer><silent> <Esc>      :call <SID>floating_input_cancel()<CR>
    nnoremap <buffer><silent> q          :call <SID>floating_input_cancel()<CR>
    inoremap <buffer><silent> <C-c> <Esc>:call <SID>floating_input_cancel()<CR>

    autocmd BufLeave <buffer> ++once call <SID>floating_input_cancel()

    " startinsert! enters insert mode at end of line on next event tick.
    startinsert!
endfun

fun! s:floating_input_finish(name) abort
    if get(b:, '_jukit_input_done', 0)
        return
    endif
    let b:_jukit_input_done = 1
    let Callback = b:_jukit_input_callback
    let winid = b:_jukit_input_winid
    if winid > 0 && nvim_win_is_valid(winid)
        call nvim_win_close(winid, v:true)
    endif
    if mode() ==# 'i'
        stopinsert
    endif
    call call(Callback, [a:name])
endfun

fun! s:floating_input_submit() abort
    let lines = nvim_buf_get_lines(0, 0, 1, v:false)
    let raw = get(lines, 0, '')
    let name = substitute(raw, '^\s*\(.\{-}\)\s*$', '\1', '')
    call s:floating_input_finish(name)
endfun

fun! s:floating_input_cancel() abort
    call s:floating_input_finish('')
endfun

" Vertical floating menu. Items is a list of display strings. j/k navigate
" the cursorline; <CR> picks the current line; <Esc>/q cancel. Calls
" Callback(idx) with the 0-based pick or -1 on cancel.
fun! jukit#util#floating_select(opts, Callback) abort
    let items = get(a:opts, 'items', [])
    if empty(items)
        call a:Callback(-1)
        return
    endif

    if !has('nvim')
        let prompt = ['[vim-jukit] ' . get(a:opts, 'title', 'Select:')]
        let i = 0
        while i < len(items)
            call add(prompt, printf('%d. %s', i + 1, items[i]))
            let i += 1
        endwhile
        let choice = inputlist(prompt)
        call a:Callback(choice >= 1 && choice <= len(items) ? choice - 1 : -1)
        return
    endif

    let title = ' ' . get(a:opts, 'title', 'Select') . ' '
    let bufnr = nvim_create_buf(v:false, v:true)
    let lines = []
    for it in items
        call add(lines, '  ' . it)
    endfor
    call nvim_buf_set_lines(bufnr, 0, -1, v:false, lines)
    call nvim_set_option_value('bufhidden', 'wipe', {'buf': bufnr})
    call nvim_set_option_value('buflisted', v:false, {'buf': bufnr})
    call nvim_set_option_value('modifiable', v:false, {'buf': bufnr})

    let width = 40
    for line in lines
        if strdisplaywidth(line) + 4 > width
            let width = strdisplaywidth(line) + 4
        endif
    endfor
    let width = min([width, &columns - 4])
    let height = min([len(lines), &lines - 4])
    let row = max([0, (&lines - height) / 2])
    let col = max([0, (&columns - width) / 2])

    let winid = nvim_open_win(bufnr, v:true, {
        \ 'relative': 'editor',
        \ 'row': row,
        \ 'col': col,
        \ 'width': width,
        \ 'height': height,
        \ 'style': 'minimal',
        \ 'border': 'rounded',
        \ 'title': title,
        \ 'title_pos': 'center',
        \ 'zindex': 60,
        \ })
    call nvim_set_option_value('cursorline', v:true, {'win': winid})

    let b:_jukit_select_callback = a:Callback
    let b:_jukit_select_winid = winid
    let b:_jukit_select_count = len(items)
    let b:_jukit_select_done = 0

    nnoremap <buffer><silent> <CR>  :call <SID>floating_select_submit()<CR>
    nnoremap <buffer><silent> <Esc> :call <SID>floating_select_cancel()<CR>
    nnoremap <buffer><silent> q     :call <SID>floating_select_cancel()<CR>
    " j/k/<Up>/<Down> navigate via the default normal-mode bindings.

    autocmd BufLeave <buffer> ++once call <SID>floating_select_cancel()
endfun

fun! s:floating_select_finish(idx) abort
    if get(b:, '_jukit_select_done', 0)
        return
    endif
    let b:_jukit_select_done = 1
    let Callback = b:_jukit_select_callback
    let winid = b:_jukit_select_winid
    if winid > 0 && nvim_win_is_valid(winid)
        call nvim_win_close(winid, v:true)
    endif
    call call(Callback, [a:idx])
endfun

fun! s:floating_select_submit() abort
    let idx = line('.') - 1
    if idx < 0 || idx >= b:_jukit_select_count
        let idx = -1
    endif
    call s:floating_select_finish(idx)
endfun

fun! s:floating_select_cancel() abort
    call s:floating_select_finish(-1)
endfun

" Prompt the user for a session name. Calls Callback(name) where name is
" the trimmed input or '' on cancel. The optional third arg is a custom
" dialog title (used by the duplicate-name re-prompt path to surface a
" "(in use)" hint without an extra echom call).
fun! jukit#util#prompt_session_name(default, Callback, ...) abort
    let title = (a:0 >= 1 && !empty(a:1)) ? a:1 : 'Session Name'
    call jukit#util#floating_input(
        \ {'prompt': '[vim-jukit] Session name: ',
        \  'default': a:default,
        \  'title': title},
        \ a:Callback)
endfun

" Show a selection list to the user. Calls Callback(idx) with the 0-based
" pick or -1 on cancel.
fun! jukit#util#select_session(items, Callback) abort
    call jukit#util#floating_select(
        \ {'items': a:items, 'title': 'Select Session'},
        \ a:Callback)
endfun

" Return the active session's name for the current buffer, or '' when
" there is no active session.
"
" Backend-agnostic: this is the canonical way for code outside the
" zellij subdir (cells.vim, send.vim, jukit_init args, etc.) to get the
" session name without poking at b:jukit_sessions directly. Backends
" without a session model (vimterm, nvimterm) always return ''.
fun! jukit#util#get_active_session_name() abort
    if !exists('b:jukit_sessions') || !exists('b:jukit_active_session')
        return ''
    endif
    if b:jukit_active_session < 0
        \ || b:jukit_active_session >= len(b:jukit_sessions)
        return ''
    endif
    return b:jukit_sessions[b:jukit_active_session].name
endfun

" List the names of every saved-output session for the current buffer's
" .py file. Scans .jukit/<py_basename>_*_outhist.json and extracts the
" middle part of each filename. The result is a sorted list of session
" name strings.
"
" Used by the "Load previous..." entry in the <leader>ss picker, and by
" the .py->.ipynb session-selection dialog (task #33). Returns [] when
" the .jukit/ directory doesn't exist or contains no per-session files.
"
" The legacy single-file <basename>_outhist.json (no session name in the
" middle) is intentionally NOT returned -- it has no associated session
" name and trying to surface it as a "Load previous" entry would be
" confusing.
fun! jukit#util#list_saved_sessions() abort
    let dir = s:resolve_jukit_dir()
    if empty(dir) || !isdirectory(dir)
        return []
    endif
    let py_basename = expand('%:p:t:r')
    if empty(py_basename)
        return []
    endif
    let prefix = py_basename . '_'
    let suffix = '_outhist.json'
    let pattern = dir . prefix . '*' . suffix
    let files = glob(pattern, 0, 1)
    let names = []
    for f in files
        let fname = fnamemodify(f, ':t')
        " strip the prefix and suffix to recover the session name
        if fname[:len(prefix)-1] !=# prefix
            continue
        endif
        if fname[-len(suffix):] !=# suffix
            continue
        endif
        let name = fname[len(prefix):-len(suffix)-1]
        if empty(name)
            continue  " legacy <basename>_outhist.json has no session name
        endif
        call add(names, name)
    endfor
    call sort(names)
    return names
endfun

" Return the absolute path of the per-session outhist json file for the
" current buffer's .py file. Defers to the empty-session legacy fallback
" when no name is given (or when there's no active session at all).
" Mirrors helpers/ipynb_convert/util.py:session_outhist_filename so the
" two language sides agree on the file name.
fun! jukit#util#session_outhist_path(...) abort
    let dir = s:resolve_jukit_dir()
    if empty(dir)
        return ''
    endif
    let py_basename = expand('%:p:t:r')
    if empty(py_basename)
        return ''
    endif
    let session = a:0 >= 1 ? a:1 : jukit#util#get_active_session_name()
    if empty(session)
        return dir . py_basename . '_outhist.json'
    endif
    return dir . py_basename . '_' . session . '_outhist.json'
endfun
