"TODO: - VARIABLE AND FUNCTION SCOPE
"      - ADD FUNTION TO CHECK WHAT THE SYSTEM CLIPBOARD IS 
"      - MAKE IT POSSIBLE TO USE NORMAL PYTHON INSTEAD OF IPYTHON WITH INLINE
"        PLOTTING
"      - AUTOMATICALLY DETECT COMMAND MARKER BASED ON FILE TYPE
"      - USE AUTOLOAD TO ORGANIZE CODE
"      - RESEARCH IF IT'S POSSIBLE TO HAVE MULTIPLE KITTY SPLITS TO SEND TO
"        FOR A SINGLE BUFFER. IDEA: make b:output_title a list, somehow keep track of
"        the last split visited, always send to the split where the cursor was
"        last

fun! s:IPythonSplit(...)
    let b:ipython = 1
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch --keep-focus --title " . b:output_title . " --cwd=current"
    if a:0 > 0
        silent exec '!kitty @ send-text --match title:' . b:output_title . " " . a:1 . "\x0d"
    endif
    silent exec '!kitty @ send-text --match title:' . b:output_title . " python " . g:plugin_path . "/helpers/check_matplotlib_backend.py " . g:plugin_path . "\x0d"
    silent exec '!kitty @ send-text --match title:' . b:output_title . " " . g:ipython_cmd . " -i -c \"\\\"import matplotlib; matplotlib.use('module://matplotlib-backend-kitty')\\\"\"\x0d"
endfun


fun! s:ReplSplit()
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch  --title " . b:output_title . " --cwd=current"
endfun


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


fun! s:SelectSection()
    set nowrapscan

    let line_before_search = line(".")
    silent! exec '/^' . b:comment_mark . ' |%%--%%|'
    if line(".")!=line_before_search
        normal! k$v
    else
        normal! G$v
    endif
    let line_before_search = line(".")
    silent! exec '?^' . b:comment_mark . ' |%%--%%|'
    if line(".")!=line_before_search
        normal! j0
    else
        normal! gg
    endif

    if g:wrapscan == 1
        set wrapscan
    endif
endfun


function! GetVisualSelection()
    "Credit: 
    "https://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript/6271254#6271254
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


fun! s:SendLine()
    if b:ipython==1
        normal! 0v$"+y
        let @x = '%paste'
    else
        normal! 0v$"xy
    endif
    silent exec <SID>ParseRegister()
    normal! j
    redraw!
endfun


fun! s:SendSelection()
    if b:ipython==1
        let @+ = <SID>GetVisualSelection() 
        let @x = '%paste'
    else
        let @x = <SID>GetVisualSelection() 
    endif
    silent exec <SID>ParseRegister()
    redraw!
endfun


fun! s:SendSection()
    call <SID>SelectSection()
    if b:ipython==1
        normal! "+y
        let @x = '%paste'
    else
        normal! "xy
    endif
    silent exec <SID>ParseRegister()
    redraw!

    set nowrapscan
    silent! exec '/^' . b:comment_mark . ' |%%--%%|'
    if g:wrapscan == 1
        set wrapscan
    endif
    nohl
    normal! j
endfun



fun! s:SendUntilCurrentSection()
    silent! exec '/^' . b:comment_mark . ' |%%--%%|'
    if b:ipython==1
        normal! k$vggj"+y
        let @x = '%paste'
    else
        normal! k$vggj"xy
    endif
    silent exec <SID>ParseRegister()
    redraw!
endfun


fun! s:SendAll()
    if b:ipython==1
        normal! ggvG$"+y
        let @x = '%paste'
    else
        normal! ggvG$"xy
    endif
    silent exec <SID>ParseRegister()
endfun


fun! s:HighlightMarkers()
    call getline(1, '$')->map({l, v -> [l+1, v =~ "^" . b:comment_mark . " |%%--%%|\s*$"]})->filter({k,v -> v[1]})->map({k,v -> v[0]})->map({k,v -> <SID>HighlightSepLines(k,v)})
    return
endfun


fun! s:HighlightSepLines(key, val)
    exe "sign place 1 line=" . a:val . " group=seperators name=seperators buffer=" . bufnr() | nohl
    return
endfun


fun! s:NewMarkerBelow()
    exec "normal! o" . b:comment_mark . " \|%%--%%\|"
    normal! j
endfun


fun! s:ToggleIPython()
    let b:ipython = (b:ipython==0)
    echo "b:ipython = " . b:ipython
endfun


fun! s:NotebookConvert(from_notebook)
    if a:from_notebook == 1
        silent exec "!python " . g:plugin_path . "/helpers/ipynb_py_convert % %:r.py"
        exec "e %:r.py"
    elseif a:from_notebook == 0
        silent exec "!python " . g:plugin_path . "/helpers/ipynb_py_convert % %:r.ipynb"
    endif
    redraw!
endfun


fun! s:SaveNBToFile(run, open, to)
    silent exec "!python " . g:plugin_path . "/helpers/ipynb_py_convert % %:r.ipynb"
    if a:run == 1
        let l:command = "!jupyter nbconvert --to " . a:to . " --allow-errors --execute --log-level='ERROR' %:r.ipynb "
    else
        let l:command = "!jupyter nbconvert --to " . a:to . " --log-level='ERROR' %:r.ipynb "
    endif
    if a:open == 1
        exec 'let l:command = l:command . "&& " . g:' . a:to . '_viewer . " %:r.' . a:to . ' &"'
    else
        let l:command = l:command . "&"
    endif
    silent! exec l:command
    redraw!
endfun


fun! s:GetPluginPath()
python3 << EOF
import vim
script_path = vim.eval('g:plugin_script_path')
path = '/'.join(script_path.split('/')[:-2])
vim.command(f"let l:plugin_path = '{path}'")
EOF
    return l:plugin_path
endfun


fun! s:InitBufVar()
    let b:ipython = g:ipython_default
    let b:comment_mark = "#"
endfun

let g:ipython_default = 0
let g:plugin_script_path = expand("<sfile>")
let g:plugin_path = <SID>GetPluginPath()
let g:pdf_viewer = "zathura"
let g:html_viewer = "firefox"
let g:ipython_cmd = '~/anaconda3/bin/ipython'
let g:wrapscan = &wrapscan

highlight seperation ctermbg=22 ctermfg=22
sign define seperators linehl=seperation

autocmd BufEnter * call <SID>InitBufVar()
autocmd BufEnter,TextChangedI,TextChanged * exe "sign unplace * group=seperators buffer=" . bufnr()
autocmd BufEnter,TextChangedI,TextChanged * call <SID>HighlightMarkers()

nnoremap <leader>tpy :call <SID>ToggleIPython()<cr>
nnoremap <leader>mm :call <SID>NewMarkerBelow()<cr>

" use the following command to execute a command in terminal before opening
" ipython. So if you want to start ipython in a virtual environment, you can
" simply use ':Ipython conda activate myvenv'
command! -nargs=1 Ipython :call <SID>IPythonSplit(<q-args>)
nnoremap <leader>ipy :call <SID>IPythonSplit()<cr>

nnoremap <leader>sp :call <SID>ReplSplit()<cr>
nnoremap <cr> :call <SID>SendLine()<cr>
vnoremap <cr> :<C-U>call <SID>SendSelection()<cr>
nmap <leader><space> :call <SID>SendSection()<cr>
nnoremap <leader>cc :call <SID>SendUntilCurrentSection()<cr><c-o>
nnoremap <leader>all :call <SID>SendAll()<cr>

nnoremap <leader><leader>np :call <SID>NotebookConvert(1)<cr>
nnoremap <leader><leader>pn :call <SID>NotebookConvert(0)<cr>
nnoremap <leader>sp :call <SID>SaveNBToFile(0,1,'pdf')<cr>
nnoremap <leader>rsp :call <SID>SaveNBToFile(1,1,'pdf')<cr>
nnoremap <leader>sh :call <SID>SaveNBToFile(0,1,'html')<cr>
nnoremap <leader>rsh :call <SID>SaveNBToFile(1,1,'html')<cr>

