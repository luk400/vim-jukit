fun s:check_filetype()
    if jukit#util#get_lang_info()[4]
        return
    endif
    echom '[vim-jukit] Filetype `' . &ft . '` not supported. Defaulting to python.'
    sleep 2
endfun

fun! s:convert_to_ipynb(args) abort
    let file_current = expand("%:p")
    let ipynb_file = expand("%:p:r") . '.ipynb'

    if !empty(glob(ipynb_file))
        let answer = confirm('[vim-jukit] ' . ipynb_file . ' already '
            \ . 'exists. Do you want to replace it?', "&Yes\n&No", 1)
        if answer == 0 || answer == 2
            return
        endif
    endif

    let out_file = system(g:_jukit_python_os_cmd . " " . jukit#util#plugin_path() . g:_jukit_ps
        \ . join(["helpers", "ipynb_convert", "convert.py "], g:_jukit_ps)
        \ . "--lang=" . &ft . ' ' . escape(file_current, ' \'))

    redraw!
    if !len(a:args)
        return
    elseif out_file =~? 'traceback (most recent call last)'
        echom '[vim-jukit] Conversion error! ' . out_file
        return
    endif

    let answer = confirm('[vim-jukit] ' . 'Converted to ' . out_file
        \ . '! Do you want to open it now?', "&Yes\n&No", 1)
    if answer == 0 || answer == 2
        return
    endif
    echom '[vim-jukit] Opening file. Press CTRL+C to cancel.'
    call system(a:args[0] . " " . escape(out_file, ' \'))
endfun

fun! s:convert_to_script() abort
    let file_current = expand("%:p")

python3 << EOF
import vim, os, sys, json
sys.path.append(vim.eval('jukit#util#plugin_path() . g:_jukit_ps . "helpers"'))
from ipynb_convert import convert

in_file = vim.eval('file_current')
out_file = convert(in_file, None, False, create=False)

vim.command(f"let out_file='{out_file}'")
EOF

    if !empty(glob(out_file))
        let answer = confirm('[vim-jukit] ' . out_file
            \ . ' already exists. Do you want to replace it?', "&Yes\n&No", 1)
        if answer == 0 || answer == 2
            return
        endif
    endif

    let cmd = g:_jukit_python_os_cmd . " " . jukit#util#plugin_path() . g:_jukit_ps
        \. join(["helpers", "ipynb_convert", "convert.py "], g:_jukit_ps)
        \. escape(file_current, ' \')
    if g:jukit_save_output
        let cmd = cmd . ' --jukit-copy'
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

    let file_current = expand("%:p")
    let fname = expand("%:p:r")
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
