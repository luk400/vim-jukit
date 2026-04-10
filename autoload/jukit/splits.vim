if g:jukit_ipython
    let s:ipython_version = system(g:jukit_shell_cmd . ' --version')
    let s:ipython_version = matchstr(s:ipython_version, '.\{-}\zs[0-9\.]\{1,}')
    let s:v_split = split(s:ipython_version, '\.')
    if !jukit#util#is_valid_version(s:v_split, g:jukit_required_ipython_version)
        echom '[vim-jukit] Insufficient ipython version! (Required version >= '
            \ . join(g:jukit_required_ipython_version, '.') . ' - Current version: '
            \ . s:ipython_version . ') -> Please update ipython!'
    endif
endif

" Zellij is the only backend with inline plotting after the 2026-04
" cleanup; vimterm/nvimterm have no graphical output channel. Force the
" inline-plotting flag off on those backends so plt.show() doesn't
" silently break.
if g:jukit_terminal !=# 'zellij' && g:jukit_inline_plotting
    echom '[vim-jukit] inline plotting only supported for value: [zellij]'
    let g:jukit_inline_plotting = 0
endif

fun! s:create_autocmd_close_splits() abort
    if exists('#jukit_auto_close#QuitPre#<buffer=' . bufnr('%', 1) . '>')
        return
    endif

    augroup jukit_auto_close
        autocmd!
        if g:jukit_terminal ==# 'zellij'
            " QuitPre: if there are visible sessions, ask the user what
            " to do. BufDelete: just persist silently (no interactive
            " prompt on buffer wipe).
            autocmd QuitPre <buffer> call jukit#zellij#splits#on_quit_pre()
            autocmd BufDelete <buffer> call jukit#zellij#splits#_persist_state()
        else
            autocmd QuitPre,BufDelete <buffer> call jukit#splits#close_output_split()
        endif
    augroup END
endfun

fun! jukit#splits#split_exists(...) abort
    exe 'return call("jukit#' . g:jukit_terminal . '#splits#exists", a:000)'
endfun

fun! jukit#splits#out_hist_scroll(down) abort
    exe 'call jukit#' . g:jukit_terminal . '#splits#out_hist_scroll(a:down)'
endfun

fun! jukit#splits#show_last_cell_output(force) abort
    " Backend-agnostic: resolves the current cell id in vim and sends
    " %jukit_out_hist <id> to the output pane via the existing send
    " dispatcher. The IPython magic clears the visible screen, prints
    " the cell-id header, and renders the saved outputs inline. Works
    " on every backend with no per-backend code.
    if !jukit#splits#split_exists('output')
        echom '[vim-jukit] No output split found. Open one with <leader>os first.'
        return
    endif

    let cell_id = jukit#util#get_current_cell_id()
    if cell_id ==# 'NONE'
        return
    endif

    " Avoid redundant re-renders unless the caller forces it. The only
    " forced caller is <leader>so itself; other callers (e.g. cells.vim
    " after delete_outputs) pass force=0 and benefit from the guard.
    if exists('g:jukit_outhist_last_cell')
        \ && g:jukit_outhist_last_cell ==# cell_id
        \ && !a:force
        return
    endif
    let g:jukit_outhist_last_cell = cell_id

    " Markdown cell branch: only meaningful on zellij, where the
    " sixelcat backend is available for rasterized math images.
    " Other backends fall through to the existing path (which prints
    " "No saved output for this cell" for markdown cells).
    if g:jukit_terminal ==# 'zellij'
        " md_buffer_vars must run before is_md_cell: the latter reads
        " b:jukit_md_start directly with no existence check, and the
        " splits.vim path historically never populated it.
        call jukit#util#md_buffer_vars()
        if jukit#util#is_md_cell(cell_id)
            let md_source = jukit#util#get_md_cell_source(cell_id)
            call jukit#util#ipython_info_write({
                \ 'md_source': md_source,
                \ 'show_latex_warning': g:jukit_show_latex_warning,
                \ })
            call jukit#send#text('%jukit_out_hist ' . cell_id . ' --md')
            return
        endif
    endif

    call jukit#send#text('%jukit_out_hist ' . cell_id)
endfun

fun! jukit#splits#close_output_split() abort
    exe 'call jukit#' . g:jukit_terminal . '#splits#close_output_split()'
endfun

fun! jukit#splits#output(...) abort
    " On zellij, splits#output is tri-state (no session → create, visible
    " → hide, hidden → show), so the "already exists, refusing" guard
    " here would block the toggle path. The zellij backend handles its
    " own existence check internally. All other backends keep the legacy
    " refusal behavior because they don't have a session model.
    if g:jukit_terminal !=# 'zellij' && jukit#splits#split_exists('output')
        echom "[vim-jukit] Output split already exists. Close it before "
            \. "creating a new one!"
        return
    endif
    call s:create_autocmd_close_splits()

    exe 'call call("jukit#' . g:jukit_terminal . '#splits#output", a:000)'
    call jukit#layouts#set_layout()
endfun

fun! jukit#splits#term() abort
    if g:jukit_terminal !=# 'zellij' && jukit#splits#split_exists('output')
        echom "[vim-jukit] Output split already exists. Close it before "
            \. "creating a new one!"
        return
    endif
    call s:create_autocmd_close_splits()

    exe 'call jukit#' . g:jukit_terminal . '#splits#term()'
    call jukit#layouts#set_layout()
endfun

fun! jukit#splits#_build_shell_cmd() abort
    let mpl_style = jukit#splits#_get_mpl_style_file()

    if g:_jukit_is_windows
        let g:_jukit_python = stridx(split(g:jukit_shell_cmd, '/')[-1], 'python') >= 0
        let g:jukit_ipython = stridx(split(g:jukit_shell_cmd, '/')[-1], 'ipython') >= 0
    else
        let g:_jukit_python = stridx(split(g:jukit_shell_cmd, '\')[-1], 'python') >= 0
        let g:jukit_ipython = stridx(split(g:jukit_shell_cmd, '\')[-1], 'ipython') >= 0
    endif
    let use_py = g:_jukit_python
    let use_ipy = g:jukit_ipython
    let shell_cmd = g:jukit_shell_cmd

    if !use_py
        return g:jukit_shell_cmd
    endif

    let cmd = "import sys;"
        \. 'sys.path.append("' . jukit#util#plugin_path() . g:_jukit_ps . 'helpers")' . ";"

    if g:jukit_custom_backend != -1
        " User-supplied custom backend wins over the built-in choices.
        let cmd = cmd
            \. "import matplotlib;"
            \. "import matplotlib.pyplot as plt;"
            \. 'matplotlib.use("module://' . g:jukit_custom_backend . '");'
            \. 'plt.show.__annotations__["save_dpi"] = ' . g:jukit_savefig_dpi . ";"
        " Zellij is the only supported inline-plotting backend after the
        " 2026-04 cleanup; the kitty/tmux paths were removed.
    elseif g:jukit_inline_plotting
        let cmd = cmd
                \. "import matplotlib;"
                \. "import matplotlib.pyplot as plt;"
                \. 'import sixelcat;'
                \. 'sixelcat.configure(max_width_factor=' . g:jukit_sixelcat_width_factor . ');'
                \. 'matplotlib.use("module://sixelcat");'
                \. 'plt.show.__annotations__["save_dpi"] = ' . g:jukit_savefig_dpi . ";"
    else
        let cmd = cmd
            \. "import matplotlib.pyplot as plt;"
            \. "from matplotlib_show_wrapper import show_wrapper;"
            \. "plt.show = show_wrapper(plt.show, " . g:jukit_mpl_block . ");"
            \. 'plt.show.__annotations__["save_dpi"] = ' . g:jukit_savefig_dpi . ";"
    endif

    if type(mpl_style) != 7
        let cmd = cmd
            \. "import matplotlib.pyplot as plt;"
            \. 'plt.style.use("' . mpl_style . '")' . ";"
    endif

    if use_ipy
        " Session name comes from the active session (zellij only). On
        " backends without a session model the helper returns '', which
        " omits the --session flag and falls back to the legacy outhist
        " filename inside %jukit_init.
        let session_name = jukit#util#get_active_session_name()
        let session_arg = empty(session_name) ? '' : (' --session=' . session_name)
        let pyfile_ws_sub = substitute(escape(expand('%:p'), '\'), ' ', '<JUKIT_WS_PH>', 'g')
        let cmd = cmd
            \. "from IPython import get_ipython;"
            \. "__shell = get_ipython();"
            \. '__shell.run_line_magic("load_ext", "jukit_run");'
            \. '__shell.run_line_magic("jukit_init", "' . pyfile_ws_sub . ' '
            \. g:jukit_in_style . ' --max_size=' . g:jukit_max_size
            \. session_arg . '");'
        if !g:jukit_debug && !g:_jukit_is_windows
            let cmd = cmd . '__shell.run_line_magic("clear", "");'
        endif
    endif

    if g:_jukit_is_windows
        let cmd = shell_cmd . " -i -c \"" . substitute(cmd, '"', g:_jukit_win_escape_char . '"', 'g') . "\""
        return cmd
    else
        let cmd = shell_cmd . " -i -c '" . cmd . "'"
        return cmd
    endif
endfun

fun! jukit#splits#_get_mpl_style_file() abort
    if g:jukit_mpl_style == ''
        return v:null
    elseif glob(g:jukit_mpl_style) == ''
        echom "[vim-jukit] Matplotlib style '" . g:jukit_mpl_style . "' not found!"
        return v:null
    endif
    return g:jukit_mpl_style
endfun
