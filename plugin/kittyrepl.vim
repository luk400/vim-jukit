"TODO: - VARIABLE AND FUNCTION SCOPE
"      - FIGURE OUT HOW TO PUT SENDSECTION MAPPING INTO A WORKING FUNTION, 
"        CURRENTLY THE PROBLEM IS THAT I CANT SELECT WITH FUNCTION
"        SelectSection AND SEND FROM INSIDE A FUNCTION, ONLY WORKS AS A
"        MAPPING VIA nmap

fun! IPythonSplit(...)
    let b:ipython = 1
    let b:output_title=strftime("%Y%m%d%H%M%S")
python3 << EOF
import vim
script_path = vim.eval('b:kittyrepl_script_path')
path = '/'.join(script_path.split('/')[:-2])
vim.command(f"let l:plugin_path = '{path}'")
EOF
    silent exec "!kitty @ launch --keep-focus --title " . b:output_title . " --cwd=current"
    if a:0 > 0
        silent exec '!kitty @ send-text --match title:' . b:output_title . " " . a:1 . "\x0d"
    endif
    silent exec '!kitty @ send-text --match title:' . b:output_title . " python " . l:plugin_path . "/helpers/check_matplotlib_backend.py " . l:plugin_path . "\x0d"
    silent exec '!kitty @ send-text --match title:' . b:output_title . " ipython -i -c \"\\\"import matplotlib; matplotlib.use('module://matplotlib-backend-kitty')\\\"\"\x0d"
endfun


fun! ReplSplit()
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch  --title " . b:output_title . " --cwd=current"
endfun


fun! ParseRegister()
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


fun! SelectSection()
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
    set nowrapscan!
endfun


function! GetVisualSelection()
    "Credit for this function goes to user 'xolox' on stackoverflow: 
    "https://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript
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


fun! SendLine()
    if b:ipython==1
        normal! 0v$"+y
        let @x = '%paste'
    else
        normal! 0v$"xy
    endif
    silent exec ParseRegister()
    normal! j
    redraw!
endfun


fun! SendSelection()
    if b:ipython==1
        let @+ = GetVisualSelection() 
        let @x = '%paste'
    else
        let @x = GetVisualSelection() 
    endif
    silent exec ParseRegister()
    redraw!
endfun


fun! SendAllUntilCurrent()
    silent! exec '/^' . b:comment_mark . ' |%%--%%|'
    if b:ipython==1
        normal! k$vggj"+y
        let @x = '%paste'
    else
        normal! k$vggj"xy
    endif
    silent exec ParseRegister()
endfun


fun! SendAll()
    if b:ipython==1
        normal! ggvG$"+y
        let @x = '%paste'
    else
        normal! ggvG$"xy
    endif
    silent exec ParseRegister()
endfun


fun! HighlightMarkers()
    call getline(1, '$')->map({l, v -> [l+1, v =~ "^" . b:comment_mark . " |%%--%%|\s*$"]})->filter({k,v -> v[1]})->map({k,v -> v[0]})->map({k,v -> HighlightSepLines(k,v)})
    return
endfun


fun! HighlightSepLines(key, val)
    exe "sign place 1 line=" . a:val . " group=seperators name=seperators buffer=" . bufnr() | nohl
    return
endfun


fun! NewMarkerBelow()
    exec "normal! o" . b:comment_mark . " \|%%--%%\|"
    normal! j
endfun


fun! ToggleIPython()
    let b:ipython = (b:ipython==0)
endfun


highlight seperation ctermbg=22 ctermfg=22
sign define seperators linehl=seperation
autocmd BufEnter * let b:comment_mark = "#"
autocmd BufEnter,TextChangedI,TextChanged * exe "sign unplace * group=seperators buffer=" . bufnr()
autocmd BufEnter,TextChangedI,TextChanged * call HighlightMarkers()

let b:ipython = 1
let b:kittyrepl_script_path=expand("<sfile>")
nnoremap <leader>tpy :call ToggleIPython()<cr>
nnoremap <leader>mm :call NewMarkerBelow()<cr>

nnoremap <leader>py :call IPythonSplit()<cr>
" use the following command to execute a command in terminal before opening
" ipython. So if you want to start ipython in a virtual environment, you can
" simply use ':Ipython conda activate myvenv'
command! -nargs=1 Ipython :call IPythonSplit(<q-args>)

nnoremap <leader>sp :call ReplSplit()<cr>
nnoremap <cr> :call SendLine()<cr>
vnoremap <cr> :<C-U>call SendSelection()<cr>
nnoremap <leader>all :call SendAll()<cr>
nnoremap <leader>cc :call SendAllUntilCurrent()<cr><c-o>
nmap <leader><space> :call SelectSection()<cr><cr>:silent! exec '/\|%%--%%\|'<cr>:nohl<cr>j

