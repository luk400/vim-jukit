fun! ReplSplit()
    let b:output_title=strftime("%Y%m%d%H%M%S")
    silent exec "!kitty @ launch  --title " . b:output_title . " --keep-focus --cwd=current"
endfun

fun! ParseRegister()
python3 << EOF
import vim 
import json

reg = vim.eval('@x') 
escaped = reg.translate(str.maketrans({
    "\n": "\\\n",
    "\\": "\\\\",
    '"': '\\"',
    "'": "\\'",
    "#": "\\#",
    "!": "\!",
    "%": "\%",
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


fun! HighlightMarkers()
    call getline(1, '$')->map({l, v -> [l+1, v =~ "^" . b:comment_mark . " |%%--%%|\s*$"]})->filter({k,v -> v[1]})->map({k,v -> v[0]})->map({k,v -> HighlightSepLines(k,v)})
    return
endfun

fun! HighlightSepLines(key, val)
    exe "sign place 1 line=" . a:val . " group=seperators name=seperators buffer=" . bufnr() | nohl
    " return 1
    return
endfun

highlight seperation ctermbg=22 ctermfg=22
sign define seperators linehl=seperation
autocmd BufEnter * let b:comment_mark = "#"
autocmd BufEnter,TextChangedI,TextChanged * exe "sign unplace * group=seperators buffer=" . bufnr()
autocmd BufEnter,TextChangedI,TextChanged * call HighlightMarkers()

nnoremap <leader>sp :call ReplSplit()<cr>
" send line
nnoremap <cr> 0v$"xy:silent exec ParseRegister()<cr>j:redraw!<cr>
" send selection
vnoremap <cr> "xy:silent exec ParseRegister()<cr>:redraw!<cr>
" send section
nmap <leader><space> :call SelectSection()<cr><cr>
" create new marker in new line below
nnoremap <leader>mm :exec "normal! o" . b:comment_mark . " \|%%--%%\|"<cr>j:nohl<cr>
" run all up until and including current section
nmap <leader>cc :exec "/" . b:comment_mark . ' \|%%--%%\|'<cr>k$vgg<cr><c-o>k:nohl<cr>
" run everything
nmap <leader>all ggvG$<cr>

