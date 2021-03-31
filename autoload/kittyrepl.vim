fun! s:SelectSection()
    set nowrapscan

    let line_before_search = line(".")
    silent! exec '/|%%--%%|'
    if line(".")!=line_before_search
        normal! k$v
    else
        normal! G$v
    endif
    let line_before_search = line(".")
    silent! exec '?|%%--%%|'
    if line(".")!=line_before_search
        normal! j0
    else
        normal! gg
    endif

    if g:wrapscan == 1
        set wrapscan
    endif
endfun


function! s:GetVisualSelection()
    "Credit for this function: 
    "httpkittyrepl#//stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript/6271254#6271254
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


fun! s:ParseRegister()
python3 << EOF
import vim 
import json

reg = vim.eval('@x')
if reg[-1]!="\n":
    reg += "\n"
escaped = reg.translate(str.maketrans({
    "\n": "\\\n",
    "\\": "\\\\",
    '"': '\\"',
    "'": "\\'",
    "#": "\\#",
    "!": "\!",
    "%": "\%",
    "|": "\|",
    }))
 
vim.command("let text = shellescape({})".format(json.dumps(escaped)))
EOF
    let command = '!kitty @ send-text --match title:' . b:output_title . ' ' . text
    return command
endfun


fun! kittyrepl#PythonSplit(...)
    let b:ipython = split(g:python_cmd, '/')[-1] == 'ipython'
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch --keep-focus --title " . b:output_title
        \ . " --cwd=current"
    if a:0 > 0
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . a:1 . "\r"
    endif
    if b:inline_plotting == 1
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " python3 " . g:plugin_path . "/helpers/check_matplotlib_backend.py "
            \ . g:plugin_path . "\r"
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . g:python_cmd . " -i -c \"\\\"import matplotlib;
            \ matplotlib.use('module://matplotlib-backend-kitty')\\\"\"\r"
    else
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . g:python_cmd . "\r"
    endif
endfun


fun! kittyrepl#ReplSplit()
    let b:ipython = 0
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch  --title " . b:output_title . " --cwd=current"
endfun


fun! kittyrepl#SendLine()
    if b:ipython==1
        normal! 0v$"+y
        let @x = '%paste'
    else
        normal! 0v$"xy
    endif
    silent exec s:ParseRegister()
    normal! j
    redraw!
endfun


fun! kittyrepl#SendSelection()
    if b:ipython==1
        let @+ = s:GetVisualSelection() 
        let @x = '%paste'
    else
        let @x = s:GetVisualSelection() 
    endif
    silent exec s:ParseRegister()
    redraw!
endfun


fun! kittyrepl#SendSection()
    call s:SelectSection()
    if b:ipython==1
        normal! "+y
        let @x = '%paste'
    else
        normal! "xy
    endif
    silent exec s:ParseRegister()
    redraw!

    set nowrapscan
    silent! exec '/|%%--%%|'
    if g:wrapscan == 1
        set wrapscan
    endif
    nohl
    normal! j
endfun



fun! kittyrepl#SendUntilCurrentSection()
    silent! exec '/|%%--%%|'
    if b:ipython==1
        normal! k$vggj"+y
        let @x = '%paste'
    else
        normal! k$vggj"xy
    endif
    silent exec s:ParseRegister()
    redraw!
endfun


fun! kittyrepl#SendAll()
    if b:ipython==1
        normal! ggvG$"+y
        let @x = '%paste'
    else
        normal! ggvG$"xy
    endif
    silent exec s:ParseRegister()
endfun


fun! kittyrepl#HighlightMarkers()
    call getline(1, '$')->map({l, v -> [l+1, v =~ "|%%--%%|"]})
        \->filter({k,v -> v[1]})->map({k,v -> v[0]})
        \->map({k,v -> kittyrepl#HighlightSepLines(k,v)})
    return
endfun


fun! kittyrepl#HighlightSepLines(key, val)
    exe "sign place 1 line=" . a:val . " group=seperators name=seperators buffer="
        \ . bufnr() | nohl
    return
endfun


fun! kittyrepl#NewMarker()
    if g:use_tcomment == 1
        exec 'normal! o|%%--%%|'
        call tcomment#operator#Line('g@$')
    else
        exec "normal! o" . b:comment_mark . ' |%%--%%|'
    endif
    normal! j
endfun


fun! kittyrepl#NotebookConvert(from_notebook)
    if a:from_notebook == 1
        silent exec "!python3 " . g:plugin_path . "/helpers/ipynb_py_convert % %:r.py"
        exec "e %:r.py"
    elseif a:from_notebook == 0
        silent exec "!python3 " . g:plugin_path . "/helpers/ipynb_py_convert % %:r.ipynb"
    endif
    redraw!
endfun


fun! kittyrepl#SaveNBToFile(run, open, to)
    silent exec "!python3 " . g:plugin_path . "/helpers/ipynb_py_convert % %:r.ipynb"
    if a:run == 1
        let command = "!jupyter nbconvert --to " . a:to
            \ . " --allow-errors --execute --log-level='ERROR' %:r.ipynb "
    else
        let command = "!jupyter nbconvert --to " . a:to . " --log-level='ERROR' %:r.ipynb "
    endif
    if a:open == 1
        exec 'let command = command . "&& " . g:' . a:to . '_viewer . " %:r.' . a:to . ' &"'
    else
        let command = command . "&"
    endif
    silent! exec command
    redraw!
endfun


fun! kittyrepl#GetPluginPath(plugin_script_path)
    let plugin_path = a:plugin_script_path
    let plugin_path = split(plugin_path, "/")[:-3]
    return "/" . join(plugin_path, "/")
endfun


fun! kittyrepl#InitBufVar()
    let b:inline_plotting = g:inline_plotting_default
    if g:use_tcomment != 1
        let b:comment_mark = g:comment_marker_default
    endif
endfun
