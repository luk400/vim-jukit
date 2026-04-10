fun s:check_filetype()
    if jukit#util#get_lang_info()[4]
        return
    endif
    echom '[vim-jukit] Filetype `' . &ft . '` not supported. Defaulting to python.'
    sleep 2
endfun

fun! s:replace_old_python_md_start() abort
    let save_view = winsaveview()
    silent! %s/^"""°°°/r"""°°°
    nohlsearch
    call winrestview(save_view)
endfun

" Returns 1 iff a legacy <basename>_outhist.json file exists in the
" current buffer's .jukit/ directory. Used by s:convert_to_ipynb to
" decide whether to surface a "(legacy)" entry in the session picker
" for users with pre-session installs.
fun! s:legacy_outhist_exists() abort
    let py_basename = expand('%:p:t:r')
    if empty(py_basename)
        return 0
    endif
    let dir = expand('%:p:h') . g:_jukit_ps . '.jukit' . g:_jukit_ps
    return filereadable(dir . py_basename . '_outhist.json')
endfun

" Build the args string passed to convert.py to drive the
" python -> ipynb output-embedding choice.
"
"   pick_idx == 0 .. n-1   : per-session entry; sessions[pick_idx]
"                            -> --session=<name>
"   pick_idx == n          : "(legacy)" entry (only present when a
"                            legacy file exists) -> no flag
"                            (convert.py defaults to legacy lookup)
"   pick_idx == n + (1|0)  : "(no outputs)" entry -> --no-outputs
fun! s:build_session_args(pick_idx, sessions, has_legacy) abort
    let n = len(a:sessions)
    if a:pick_idx < n
        return ' --session=' . a:sessions[a:pick_idx]
    endif
    if a:has_legacy && a:pick_idx == n
        " "(legacy)" -> let convert.py default-fall through to the
        " <basename>_outhist.json file (its session arg is "").
        return ''
    endif
    return ' --no-outputs'
endfun

fun! s:convert_to_ipynb(args) abort
    " for compatibility with vim-jukit < 1.3.4:
    call s:replace_old_python_md_start()
    write

    let ipynb_file = escape(expand("%:p:r"), ' \') . '.ipynb'

    " Overwrite check stays inline -- it has to happen before we
    " offer the session picker so that "no, don't overwrite"
    " short-circuits the entire flow.
    if !empty(glob(ipynb_file)) && g:jukit_convert_overwrite_default == -1
        let answer = confirm('[vim-jukit] ' . ipynb_file . ' already '
            \ . 'exists. Do you want to replace it?', "&Yes\n&No", 1)
        if answer == 0 || answer == 2
            return
        endif
    elseif g:jukit_convert_overwrite_default == 0
        echom '[vim-jukit] Converting unsuccessful: ' . ipynb_file . ' already exists!'
        sleep 500m
        return
    endif

    " Build session picker items: [per-session names...] + [legacy] +
    " [no outputs]. The picker only fires if there's at least one
    " saved-output file (per-session OR legacy) -- otherwise we just
    " convert with --no-outputs synchronously, matching the previous
    " "no outhist file -> empty notebook" behavior without an extra
    " click.
    let sessions = jukit#util#list_saved_sessions()
    let has_legacy = s:legacy_outhist_exists()

    if empty(sessions) && !has_legacy
        " No saved outputs anywhere -> just convert without prompting.
        " --no-outputs is implicit (convert.py would find no file
        " either way), but we pass it explicitly to be unambiguous.
        call s:run_convert_to_ipynb(' --no-outputs', a:args)
        return
    endif

    let items = copy(sessions)
    if has_legacy
        call add(items, '(legacy outhist)')
    endif
    call add(items, '(no outputs - clean notebook)')

    call jukit#util#floating_select(
        \ {'items': items, 'title': 'Select Session Outputs'},
        \ {idx -> s:after_pick_session_for_ipynb(
        \           idx, sessions, has_legacy, a:args)})
endfun

fun! s:after_pick_session_for_ipynb(idx, sessions, has_legacy, viewer_args) abort
    if a:idx < 0
        echom '[vim-jukit] conversion cancelled'
        return
    endif
    let session_arg = s:build_session_args(a:idx, a:sessions, a:has_legacy)
    call s:run_convert_to_ipynb(session_arg, a:viewer_args)
endfun

" Actually run convert.py and dispatch the post-convert open prompt.
" Split out from s:convert_to_ipynb so the picker callback path and
" the no-saved-outputs short-circuit path share the same body.
fun! s:run_convert_to_ipynb(extra_args, viewer_args) abort
    let file_current = escape(expand("%:p"), ' \')

    let out_file = system(g:_jukit_python_os_cmd . " " . jukit#util#plugin_path() . g:_jukit_ps
        \ . join(["helpers", "ipynb_convert", "convert.py "], g:_jukit_ps)
        \ . "--lang=" . &ft . a:extra_args . ' ' . escape(file_current, ' \'))

    redraw!
    if !len(a:viewer_args)
        return
    elseif out_file =~? 'traceback (most recent call last)'
        echom '[vim-jukit] Conversion error! ' . out_file
        return
    endif

    if g:jukit_convert_open_default == -1
        let answer = confirm('[vim-jukit] ' . 'Converted to ' . out_file
            \ . '! Do you want to open it now?', "&Yes\n&No", 1)
        if answer == 0 || answer == 2
            return
        endif
    elseif g:jukit_convert_open_default == 0
        echom '[vim-jukit] Converted to ' . out_file[:-2] . '...'
        sleep 500m
        return
    endif

    echom '[vim-jukit] Opening file. Press CTRL+C to cancel.'
    call system(a:viewer_args[0] . " " . escape(out_file, ' \'))
endfun

fun! s:convert_to_script() abort
    let file_current = escape(expand("%:p"), ' \')

    " Compute the output filename (so we can do the overwrite check) AND
    " peek at whether the .ipynb has any saved outputs (so we know
    " whether to prompt for a session-save name). Both happen in a
    " single python block to avoid loading the .ipynb twice.
python3 << EOF
import vim, os, sys, json
sys.path.append(vim.eval('jukit#util#plugin_path() . g:_jukit_ps . "helpers"'))
from ipynb_convert import convert

in_file = vim.eval('file_current')
out_file = convert(in_file, None, False, create=False)

# Check whether any code cell has at least one stored output entry,
# so we only prompt for a session name when there's actually something
# to save under it.
try:
    with open(in_file) as _f:
        _nb = json.load(_f)
    _has_outputs = any(
        cell.get('outputs')
        for cell in _nb.get('cells', [])
        if cell.get('cell_type') == 'code'
    )
except Exception:
    _has_outputs = False

vim.command(f"let out_file='{out_file}'")
vim.command(f"let nb_has_outputs={int(bool(_has_outputs))}")
EOF

    if !empty(glob(out_file)) && g:jukit_convert_overwrite_default == -1
        let answer = confirm('[vim-jukit] ' . out_file
            \ . ' already exists. Do you want to replace it?', "&Yes\n&No", 1)
        if answer == 0 || answer == 2
            return
        endif
    elseif g:jukit_convert_overwrite_default == 0
        echom '[vim-jukit] Converting unsuccessful: ' . out_file . ' already exists!'
        sleep 500m
        return
    endif

    " Async branch: g:jukit_save_output is on AND the notebook has at
    " least one stored output -> prompt for a session name to save
    " the outputs under (default _original_outputs_converted_), then
    " run convert.py in the callback. Otherwise just run synchronously.
    if g:jukit_save_output && nb_has_outputs
        let file_current_local = file_current
        call jukit#util#prompt_session_name(
            \ '_original_outputs_converted_',
            \ {n -> s:after_pick_session_for_script(n, file_current_local)},
            \ 'Session Save Name')
        return
    endif

    call s:run_convert_to_script(file_current, '')
endfun

" Continuation: the user supplied (or cancelled) a session-save name
" for the .ipynb -> .py conversion. Empty submission cancels the whole
" conversion since the user was in the middle of an output-saving flow.
fun! s:after_pick_session_for_script(name, file_current) abort
    if empty(a:name)
        echom '[vim-jukit] conversion cancelled'
        return
    endif
    " Validate against the same charset rule as the session picker so
    " the saved filename is filesystem-safe.
    if a:name !~# '^[A-Za-z0-9_-]\+$'
        echom '[vim-jukit] Session name "' . a:name . '" is invalid. '
            \. 'Use only A-Z, a-z, 0-9, _ and -.'
        let file_current = a:file_current
        call jukit#util#prompt_session_name(
            \ '_original_outputs_converted_',
            \ {n -> s:after_pick_session_for_script(n, file_current)},
            \ 'Session Save Name (invalid chars)')
        return
    endif
    call s:run_convert_to_script(a:file_current, ' --session-save=' . a:name)
endfun

" Actually run convert.py for the .ipynb -> .py conversion. Split out
" of s:convert_to_script so the no-prompt path and the picker callback
" path share the same body.
fun! s:run_convert_to_script(file_current, session_arg) abort
    let cmd = g:_jukit_python_os_cmd . " " . jukit#util#plugin_path() . g:_jukit_ps
        \. join(["helpers", "ipynb_convert", "convert.py "], g:_jukit_ps)
        \. escape(a:file_current, ' \')
    if g:jukit_save_output
        let cmd = cmd . ' --jukit-copy' . a:session_arg
    endif

    let response = system(cmd)
    if response =~? 'error' || response =~? 'traceback (most recent call last)'
        echom '[vim-jukit] Conversion error! ' . response
        return
    endif
    exe 'e ' . escape(response, ' \')
endfun

fun! jukit#convert#notebook_convert(...) abort
    " Converts from .ipynb to .py and vice versa

    write
    if expand("%:e") == "ipynb"
        call s:convert_to_script()
    else
        call s:check_filetype()
        call s:convert_to_ipynb(a:000)
    endif
    redraw!
endfun

fun! jukit#convert#save_nb_to_file(run, open, to) abort
    " Converts the existing .ipynb to the given filetype (a:to) - e.g. html or
    " pdf - and open with specified file viewer

    call s:check_filetype()
    write
    echom "[vim-jukit] Converting..."
    let viewer = get(g:, 'jukit_' . a:to . '_viewer', v:null)
    if type(viewer) == 7
        echom '[vim-jukit] Variable `g:jukit_' . a:to . '_viewer` not set! '
            \. 'Defaulting to `g:jukit_' . a:to . '_viewer`="xdg-open"`'
        let viewer = 'xdg-open'
    endif

    let file_current = escape(expand("%:p"), ' \')
    let fname = escape(expand("%:p:r"), ' \')
    let ipynb_file = fname . '.ipynb'
    let html_theme = get(g:, 'jukit_html_theme', 'dark')
    call system(g:_jukit_python_os_cmd . " " . jukit#util#plugin_path() . g:_jukit_ps
        \ . join(["helpers", "ipynb_convert", "convert.py "], g:_jukit_ps)
        \ . "--lang=" . &ft . ' ' . escape(file_current, ' \'))

    let rerun = a:run ? ' --execute' : ''
    let cmd = "jupyter nbconvert --to " . a:to . rerun . " --allow-errors"
        \ . " --log-level='ERROR' --HTMLExporter.theme=" . html_theme
        \ . " " . ipynb_file

    if a:open == 1
        let cmd = cmd . " && " . viewer . " " . fname . "." . a:to . " &"
    else
        let cmd = cmd . " &"
    endif
    call system(cmd)
    redraw!
endfun
