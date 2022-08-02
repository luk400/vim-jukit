if g:jukit_terminal == 'kitty'
    let s:invalid_kitty_version = jukit#kitty#cmd#invalid_version(g:jukit_required_kitty_version)
    if len(s:invalid_kitty_version) && has('nvim')
        let g:jukit_terminal = 'nvimterm'
    elseif len(s:invalid_kitty_version)
        let g:jukit_terminal = 'vimterm'
    endif

    if len(s:invalid_kitty_version)
        echom '[vim-jukit] Insufficient kitty version! (Required version >= ' 
            \ . join(g:jukit_required_kitty_version, '.') . ' - Current version: '
            \ . join(s:invalid_kitty_version, '.') . ") -> using " 
            \ . g:jukit_terminal . ' instead!'
    else
        let g:jukit_mpl_style = jukit#util#plugin_path()
            \ . g:_jukit_ps . join(['helpers', 'matplotlib-backend-kitty', 'backend.mplstyle'], g:_jukit_ps)
    endif
endif

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

let s:supported_graphical_term = ['kitty', 'tmux']
let s:inline_plot_psbl = index(s:supported_graphical_term, g:jukit_terminal) >= 0
if !s:inline_plot_psbl && g:jukit_inline_plotting
    echom '[vim-jukit] inline plotting only supported for values: [' 
        \. join(s:supported_graphical_term, ', ') . ']'
    let g:jukit_inline_plotting = 0
endif

fun! s:create_autocmd_close_splits() abort
    if exists('#jukit_auto_close#QuitPre#<buffer=' . bufnr('%', 1) . '>')
        return
    endif

    augroup jukit_auto_close
        autocmd!
        autocmd QuitPre,BufDelete <buffer> call jukit#splits#close_output_and_history(1)
    augroup END
endfun

fun! jukit#splits#split_exists(...) abort
    exe 'return call("jukit#' . g:jukit_terminal . '#splits#exists", a:000)'
endfun

fun! jukit#splits#out_hist_scroll(down) abort
    exe 'call jukit#' . g:jukit_terminal . '#splits#out_hist_scroll(a:down)'
endfun

fun! jukit#splits#show_last_cell_output(force) abort
    if !jukit#splits#split_exists('outhist')
        echom '[vim-jukit] Output-history split not found. Please create if first.'
        return
    endif
    exe 'call jukit#' . g:jukit_terminal . '#splits#show_last_cell_output(a:force)'
endfun

fun! jukit#splits#close_history() abort
    exe 'call jukit#' . g:jukit_terminal . '#splits#close_history()'
endfun

fun! jukit#splits#close_output_split() abort
    exe 'call jukit#' . g:jukit_terminal . '#splits#close_output_split()'
endfun

fun! jukit#splits#output(...) abort
    if jukit#splits#split_exists('output')
        echom "[vim-jukit] Output split already exists. Close it before "
            \. "creating a new one!"
        return
    endif
    call s:create_autocmd_close_splits()

    exe 'call call("jukit#' . g:jukit_terminal . '#splits#output", a:000)'
    call jukit#layouts#set_layout()
endfun

fun! jukit#splits#term() abort
    if jukit#splits#split_exists('output')
        echom "[vim-jukit] Output split already exists. Close it before "
            \. "creating a new one!"
        return
    endif
    call s:create_autocmd_close_splits()

    exe 'call jukit#' . g:jukit_terminal . '#splits#term()'
    call jukit#layouts#set_layout()
endfun

fun! jukit#splits#history() abort
    if jukit#splits#split_exists('outhist')
        echom "[vim-jukit] Output-history split already exists. Close it "
            \. "before creating a new one!"
        return
    endif
    call s:create_autocmd_close_splits()

    exe 'call jukit#' . g:jukit_terminal . '#splits#history()'
    call jukit#layouts#set_layout()
    call jukit#splits#show_last_cell_output(1)
endfun

fun! jukit#splits#close_output_and_history(confirm) abort
    exe 'let outhist_exists = jukit#' . g:jukit_terminal . '#splits#exists("outhist")'
    exe 'let output_exists = jukit#' . g:jukit_terminal . '#splits#exists("output")'

    if a:confirm && (outhist_exists || output_exists)
        let answer = confirm("[vim-jukit] Do you want to close split windows?", "&Yes\n&No", 1)
        if answer == 0 || answer == 2
            return
        endif
    endif

    if outhist_exists
        exe 'call jukit#' . g:jukit_terminal . '#splits#close_history()'
    endif

    if output_exists
        exe 'call jukit#' . g:jukit_terminal . '#splits#close_output_split()'
    endif
    redraw!
endfun

fun! jukit#splits#toggle_auto_hist(...) abort
    let au_exists = exists('#jukit_auto_output#CursorHold')
    let enable_au = a:0 > 0 ? a:1 : !au_exists

    if !au_exists && enable_au
	echom "[vim-jukit] Enabled auto output history! (CursorHold updatetime: " . &updatetime . ")"
        augroup jukit_auto_output
            autocmd!
            autocmd CursorHold <buffer> call jukit#splits#show_last_cell_output(0)
        augroup END
    elseif au_exists && !enable_au
	echom "[vim-jukit] Disabled auto output history!"
        augroup jukit_auto_output
            autocmd!
        augroup END
    endif
endfun

fun! jukit#splits#output_and_history(...) abort
    if a:0 > 0
        call jukit#splits#output(a:1)
    else
        call jukit#splits#output()
    endif
    call jukit#splits#history()
endfun

fun! jukit#splits#_build_shell_cmd(...) abort
    let mpl_style = jukit#splits#_get_mpl_style_file()
    let is_outhist = a:0 > 0 && a:1 == 'outhist'

    if !is_outhist
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
    else
        let use_py = 1
        let use_ipy = 1
        let shell_cmd = 'ipython3'
    endif

    if !use_py
        return g:jukit_shell_cmd
    endif

    let cmd = "import sys;"
        \. 'sys.path.append("' . jukit#util#plugin_path() . g:_jukit_ps . 'helpers")' . ";"

    if g:jukit_inline_plotting
        let cmd = cmd
                \. "import matplotlib;"
                \. "import matplotlib.pyplot as plt;"

        if g:jukit_terminal == 'kitty'
            let cmd = cmd
                \. 'matplotlib.use("module://matplotlib-backend-kitty");'
                \. 'plt.show.__annotations__["save_dpi"] = ' . g:jukit_savefig_dpi . ";"
        elseif g:jukit_terminal == 'tmux'
            let current_pane = matchstr(system('tmux run "echo #{pane_id}"'), '%\d*')
            if is_outhist
                let target_pane = g:jukit_outhist_title
            else
                let target_pane = g:jukit_output_title
            endif
            let cmd = cmd
                \. 'matplotlib.use("module://imgcat");'
                \. 'plt.show.__annotations__["tmux_panes"] = ["' 
                \. current_pane . '", "' . target_pane . '"];'
                \. 'plt.show.__annotations__["save_dpi"] = ' . g:jukit_savefig_dpi . ";"
        else
            echom "[vim-jukit] No inline plotting for `g:jukit_terminal = "
                \ . g:jukit_terminal . "` supported"
        endif
    elseif g:jukit_custom_backend != -1
        let cmd = cmd
            \. 'matplotlib.use("module://' . g:jukit_custom_backend . '");'
            \. 'plt.show.__annotations__["save_dpi"] = ' . g:jukit_savefig_dpi . ";"

    elseif !is_outhist
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
        let pyfile_ws_sub = substitute(escape(expand('%:p'), ' \'), ' ', '<JUKIT_WS_PH>', 'g')
        let cmd = cmd
            \. "from IPython import get_ipython;"
            \. "__shell = get_ipython();"
            \. '__shell.run_line_magic("load_ext", "jukit_run");'
            \. '__shell.run_line_magic("jukit_init", "' . pyfile_ws_sub . ' '
            \. g:jukit_in_style . ' --max_size=' . g:jukit_max_size . '");'
        if !g:jukit_debug && !g:_jukit_is_windows
            let cmd = cmd . '__shell.run_line_magic("clear", "");'
        endif
    endif

    if g:_jukit_is_windows
        let cmd = shell_cmd . " -i -c \"" . escape(cmd, '"') . "\""
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
