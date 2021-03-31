fun! s:SelectSection()
    " Selects the text between 2 cell markers
    
    set nowrapscan

    let line_before_search = line(".")
    silent! exec '/|%%--%%|'
    " check if line has changed, otherwise no section AFTER the current one
    " was found
    if line(".")!=line_before_search
        normal! k$v
    else
        normal! G$v
    endif
    let line_before_search = line(".")
    silent! exec '?|%%--%%|'
    " check if line has changed, otherwise not section BEFORE the current one
    " was found
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


fun! s:ParseRegister()
    " Gets content of register and send to kitty window
    
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
 
vim.command("let escaped_text = shellescape({})".format(json.dumps(escaped)))
EOF
    let command = '!kitty @ send-text --match title:' . b:output_title . ' ' . escaped_text
    return command
endfun


fun! kittyrepl#PythonSplit(...)
    " Opens new kitty window split and opens python

    " check if ipython is used
    let b:ipython = split(g:python_cmd, '/')[-1] == 'ipython'
    " define title of new kitty window by which we match when sending
    let b:output_title=strftime("%Y%m%d%H%M%S")
    " create new window
    silent exec "!kitty @ launch --keep-focus --title " . b:output_title
        \ . " --cwd=current"

    " if an argument was given, execute it in new kitty terminal window before
    " starting python shell
    if a:0 > 0
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . a:1 . "\r"
    endif

    if b:inline_plotting == 1
        " if inline plotting is enabled, use helper script to check if the
        " required backend is in python path and otherwise create it
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " python3 " . g:plugin_path . "/helpers/check_matplotlib_backend.py "
            \ . g:plugin_path . "\r"
        " open python and import the matplotlib with the backend required
        " backend first
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . g:python_cmd . " -i -c \"\\\"import matplotlib;
            \ matplotlib.use('module://matplotlib-backend-kitty')\\\"\"\r"
    else
        " if no inline plotting is desired, simply open python
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . g:python_cmd . "\r"
    endif
endfun


fun! kittyrepl#ReplSplit()
    " Opens a new kitty terminal window

    let b:ipython = 0
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch  --title " . b:output_title . " --cwd=current"
endfun


fun! kittyrepl#SendLine()
    " Sends a single line to the other kitty terminal window

    if b:ipython==1
        " if ipython is used, copy code to system clipboard and '%paste'
        " to register
        normal! 0v$"+y
        let @x = '%paste'
    else
        " otherwise yank line to register
        normal! 0v$"xy
    endif
    " send register content to window
    silent exec s:ParseRegister()
    normal! j
    redraw!
endfun


fun! kittyrepl#SendSelection()
    " Sends visually selected text to the other kitty terminal window
    
    if b:ipython==1
        " if ipython is used, copy visual selection to system clipboard and 
        " '%paste' to register
        let @+ = s:GetVisualSelection() 
        let @x = '%paste'
    else
        " otherwise yank content of visual selection to register
        let @x = s:GetVisualSelection() 
    endif
    " send register content to window
    silent exec s:ParseRegister()
    redraw!
endfun


fun! kittyrepl#SendSection()
    " Sends the section of current cursor position to window

    " first select the whole current section
    call s:SelectSection()
    if b:ipython==1
        " if ipython is used, copy whole section to system clipboard and 
        " '%paste' to register
        normal! "+y
        let @x = '%paste'
    else
        " otherwise yank content of section to register
        normal! "xy
    endif
    " send register content to window
    silent exec s:ParseRegister()
    redraw!

    set nowrapscan
    " move to next section
    silent! exec '/|%%--%%|'
    if g:wrapscan == 1
        set wrapscan
    endif
    nohl
    normal! j
endfun



fun! kittyrepl#SendUntilCurrentSection()
    " Sends all code until (and including) the current section to window

    " go to end of current section
    silent! exec '/|%%--%%|'
    if b:ipython==1
        " if ipython is used, copy from end of current section until 
        " file beginning to system clipboard and yank '%paste' to register
        normal! k$vggj"+y
        let @x = '%paste'
    else
        " otherwise simply yank everything from beginning to current
        " section to register
        normal! k$vggj"xy
    endif
    " send register content to window
    silent exec s:ParseRegister()
    redraw!
endfun


fun! kittyrepl#SendAll()
    " Sends all code in file to window
    
    if b:ipython==1
        " if ipython is used, copy all code in file  to system clipboard 
        " and yank '%paste' to register
        normal! ggvG$"+y
        let @x = '%paste'
    else
        " otherwise copy yank whole file content to register
        normal! ggvG$"xy
    endif
    " send register content to window
    silent exec s:ParseRegister()
endfun


fun! kittyrepl#HighlightMarkers()
    " Highlights all cell markers in file
    
    call getline(1, '$')->map({l, v -> [l+1, v =~ "|%%--%%|"]})
        \->filter({k,v -> v[1]})->map({k,v -> v[0]})
        \->map({k,v -> s:HighlightSepLines(k,v)})
    return
endfun


fun! s:HighlightSepLines(key, val)
    " used by kittyrepl#HighlightMarkers() to highlight markers
    
    exe "sign place 1 line=" . a:val . " group=seperators name=seperators buffer="
        \ . bufnr() | nohl
    return
endfun


fun! kittyrepl#NewMarker()
    " Creates a new cell marker below

    if g:use_tcomment == 1
        " use tcomment plugin to automaticall detect comment marker of 
        " current filetype and comment line if specified
        exec 'normal! o |%%--%%|'
        call tcomment#operator#Line('g@$')
    else
        " otherwise simply prepend line with user b:comment_marker variable
        exec "normal! o" . b:comment_mark . ' |%%--%%|'
    endif
    normal! j
endfun


fun! kittyrepl#NotebookConvert(from_notebook)
    " Converts from .ipynb to .py if a:from_notebook==1 and the otherway if
    " a:from_notebook==0

    if a:from_notebook == 1
        silent exec "!python3 " . g:plugin_path . "/helpers/ipynb_py_convert % %:r.py"
        exec "e %:r.py"
    elseif a:from_notebook == 0
        silent exec "!python3 " . g:plugin_path . "/helpers/ipynb_py_convert % %:r.ipynb"
    endif
    redraw!
endfun


fun! kittyrepl#SaveNBToFile(run, open, to)
    " Converts the existing .ipynb to the given filetype (a:to) - e.g. html or
    " pdf - and open with specified file viewer

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
    " Gets the absolute path to the plugin (i.e. to the folder vim-jukit/) 
    
    let plugin_path = a:plugin_script_path
    let plugin_path = split(plugin_path, "/")[:-3]
    return "/" . join(plugin_path, "/")
endfun


fun! kittyrepl#InitBufVar()
    " Initialize buffer variables

    let b:inline_plotting = g:inline_plotting_default
    if g:use_tcomment != 1
        let b:comment_mark = g:comment_marker_default
    endif
endfun
