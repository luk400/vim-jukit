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

    let &wrapscan = s:wrapscan
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

reg = vim.eval('s:jukit_register')
reg_conent = vim.eval(f'@{reg}')
if reg_conent[-1]!="\n":
    reg_conent += "\n"
escaped = reg_conent.translate(str.maketrans({
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


fun! jukit#PythonSplit(...)
    " Opens new kitty window split and opens python

    " check if ipython is used
    let b:ipython = split(s:jukit_python_cmd, '/')[-1] == 'ipython'
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
        " open python, add path to backend  and import matplotlib with the required
        " backend first
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . s:jukit_python_cmd . " -i -c \"\\\"import sys;
            \ sys.path.append('" . s:plugin_path . "/helpers'); import matplotlib;
            \ matplotlib.use('module://matplotlib-backend-kitty')\\\"\"\r"
    else
        " if no inline plotting is desired, simply open python
        silent exec '!kitty @ send-text --match title:' . b:output_title
            \ . " " . s:jukit_python_cmd . "\r"
    endif
endfun


fun! jukit#WindowSplit()
    " Opens a new kitty terminal window

    let b:ipython = 0
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch  --title " . b:output_title . " --cwd=current"
endfun


fun! jukit#SendLine()
    " Sends a single line to the other kitty terminal window

    if b:ipython==1
        " if ipython is used, copy code to system clipboard and '%paste'
        " to register
        normal! 0v$"+y
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise yank line to register
        exec 'normal! 0v$"' . s:jukit_register . 'y'
    endif
    " send register content to window
    silent exec s:ParseRegister()
    normal! j
    redraw!
endfun


fun! jukit#SendSelection()
    " Sends visually selected text to the other kitty terminal window
    
    if b:ipython==1
        " if ipython is used, copy visual selection to system clipboard and 
        " '%paste' to register
        let @+ = s:GetVisualSelection() 
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise yank content of visual selection to register
        exec 'let @' . s:jukit_register . ' = s:GetVisualSelection()'
    endif
    " send register content to window
    silent exec s:ParseRegister()
    redraw!
endfun


fun! jukit#SendSection()
    " Sends the section of current cursor position to window

    " first select the whole current section
    call s:SelectSection()
    if b:ipython==1
        " if ipython is used, copy whole section to system clipboard and 
        " '%paste' to register
        normal! "+y
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise yank content of section to register
        exec 'normal! "' . s:jukit_register . 'y'
    endif
    " send register content to window
    silent exec s:ParseRegister()
    redraw!

    set nowrapscan
    " move to next section
    silent! exec '/|%%--%%|'
    let &wrapscan = s:wrapscan
    nohl
    normal! j
endfun


fun! jukit#SendUntilCurrentSection()
    " Sends all code until (and including) the current section to window

    " save current window view to restore after jumping to file beginning
    let save_view = winsaveview()
    " go to end of current section
    silent! exec '/|%%--%%|'
    if b:ipython==1
        " if ipython is used, copy from end of current section until 
        " file beginning to system clipboard and yank '%paste' to register
        normal! k$vggj"+y
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise simply yank everything from beginning to current
        " section to register
        exec 'normal! k$vggj"' . s:jukit_register . 'y'
    endif
    " send register content to window
    silent exec s:ParseRegister()
    " restore previous window view
    call winrestview(save_view)
    nohl
    redraw!
endfun


fun! jukit#SendAll()
    " Sends all code in file to window
    
    if b:ipython==1
        " if ipython is used, copy all code in file  to system clipboard 
        " and yank '%paste' to register
        normal! ggvG$"+y
        exec 'let @' . s:jukit_register . " = '%paste'"
    else
        " otherwise copy yank whole file content to register
        exec 'normal! ggvG$"' . s:jukit_register . 'y'
    endif
    " send register content to window
    silent exec s:ParseRegister()
endfun


fun! jukit#NewMarker()
    " Creates a new cell marker below

    if s:jukit_use_tcomment == 1
        " use tcomment plugin to automaticall detect comment mark of 
        " current filetype and comment line if specified
        exec 'normal! o |%%--%%|'
        call tcomment#operator#Line('g@$')
    else
        " otherwise simply prepend line with user b:comment_mark variable
        exec "normal! o" . b:comment_mark . ' |%%--%%|'
    endif
    normal! j
endfun


fun! jukit#NotebookConvert(from_notebook)
    " Converts from .ipynb to .py if a:from_notebook==1 and the otherway if
    " a:from_notebook==0

    if a:from_notebook == 1
        silent exec "!" . s:python_path . " " . s:plugin_path . "/helpers/ipynb_py_convert " 
            \ . expand("%") . " " . expand("%:r") . '.py'
        exec 'e ' . expand("%:r") . '.py'
    elseif a:from_notebook == 0
        silent exec "!" . s:python_path . " " . s:plugin_path . "/helpers/ipynb_py_convert "
            \ . expand("%") . " " . expand("%:r") . '.ipynb'
    endif
    redraw!
endfun


fun! jukit#SaveNBToFile(run, open, to)
    " Converts the existing .ipynb to the given filetype (a:to) - e.g. html or
    " pdf - and open with specified file viewer

    silent exec "!" . s:python_path . " " . s:plugin_path . "/helpers/ipynb_py_convert "
        \ . expand("%") . " " . expand("%:r") . '.ipynb'
    if a:run == 1
        let command = "!jupyter nbconvert --to " . a:to
            \ . " --allow-errors --execute --log-level='ERROR' "
            \ . expand("%:r") . '.ipynb '
    else
        let command = "!jupyter nbconvert --to " . a:to . " --log-level='ERROR' "
            \ . expand("%:r") . '.ipynb '
    endif
    if a:open == 1
        exec 'let command = command . "&& " . g:jukit_' . a:to . '_viewer . " '
            \ . expand("%:r") . '.' . a:to . ' &"'
    else
        let command = command . "&"
    endif
    silent! exec command
    redraw!
endfun


fun! jukit#GetPluginPath(plugin_script_path)
    " Gets the absolute path to the plugin (i.e. to the folder vim-jukit/) 
    
    let plugin_path = a:plugin_script_path
    let plugin_path = split(plugin_path, "/")[:-3]
    return "/" . join(plugin_path, "/")
endfun


fun! s:InitBufVar()
    " Initialize buffer variables

    let b:inline_plotting = s:jukit_inline_plotting_default
    if s:jukit_use_tcomment != 1
        let b:comment_mark = s:jukit_comment_mark_default
    endif
endfun


""""""""""""""""""
" helper variables
let s:wrapscan = &wrapscan 
let s:plugin_path = jukit#GetPluginPath(expand("<sfile>"))

" get path of python executable that vim is using
python3 << EOF
import vim
import sys
vim.command("let s:python_path = '{}'".format(sys.executable))
EOF


"""""""""""""""""""""""""
" User defined variables:
let s:jukit_use_tcomment = get(g:, 'jukit_use_tcomment', 0)
let s:jukit_inline_plotting_default = get(g:, 'jukit_inline_plotting_default', 1)
let s:jukit_comment_mark_default = get(g:, 'jukit_comment_mark_default', '#')
let s:jukit_python_cmd = get(g:, 'jukit_python_cmd', 'python')
let s:jukit_register = get(g:, 'jukit_register', 'x')
let g:jukit_html_viewer = 'firefox'


"""""""""""""""""""""""""""""
" initialize buffer variables
call s:InitBufVar()
autocmd BufEnter * call s:InitBufVar()
