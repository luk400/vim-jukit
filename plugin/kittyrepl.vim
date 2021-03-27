"TODO: - VARIABLE AND FUNCTION SCOPE
"      - FIGURE OUT HOW TO PUT SENDSECTION MAPPING INTO A WORKING FUNTION, 
"        CURRENTLY THE PROBLEM IS THAT I CANT SELECT WITH FUNCTION
"        SelectSection AND SEND FROM INSIDE A FUNCTION, ONLY WORKS AS A
"        MAPPING VIA nmap

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

fun! SendLine(ipython)
    if a:ipython==1
        normal! 0v$"+y
        let @x = '%paste'
    else
        normal! 0v$"xy
    endif
    silent exec ParseRegister()
    normal! j
    redraw!
endfun

fun! SendSelection(ipython)
    if a:ipython==1
        let @+ = GetVisualSelection() 
        let @x = '%paste'
    else
        let @x = GetVisualSelection() 
    endif
    silent exec ParseRegister()
    redraw!
endfun

fun! SendAllUntilCurrent(ipython)
    silent! exec '/^' . b:comment_mark . ' |%%--%%|'
    if a:ipython==1
        normal! k$vggj"+y
        let @x = '%paste'
    else
        normal! k$vggj"xy
    endif
    silent exec ParseRegister()
endfun

fun! SendAll(ipython)
    if a:ipython==1
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
    nnoremap <cr> :call SendLine(b:ipython)<cr>
    vnoremap <cr> :<C-U>call SendSelection(b:ipython)<cr>
    nnoremap <leader>all :call SendAll(b:ipython)<cr>
    nnoremap <leader>cc :call SendAllUntilCurrent(b:ipython)<cr>
endfun


highlight seperation ctermbg=22 ctermfg=22
sign define seperators linehl=seperation
autocmd BufEnter * let b:comment_mark = "#"
autocmd BufEnter,TextChangedI,TextChanged * exe "sign unplace * group=seperators buffer=" . bufnr()
autocmd BufEnter,TextChangedI,TextChanged * call HighlightMarkers()

nnoremap <leader>sp :call ReplSplit()<cr>
nnoremap <leader>mm :call NewMarkerBelow()<cr>
nnoremap <leader>ipy :call ToggleIPython()<cr>

let b:ipython = 0
nnoremap <cr> :call SendLine(b:ipython)<cr>
vnoremap <cr> :<C-U>call SendSelection(b:ipython)<cr>
nnoremap <leader>all :call SendAll(b:ipython)<cr>
nnoremap <leader>cc :call SendAllUntilCurrent(b:ipython)<cr>
nmap <leader><space> :call SelectSection()<cr><cr>:silent! exec '/\|%%--%%\|'<cr>:nohl<cr>j



