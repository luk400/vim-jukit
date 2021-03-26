fun! ReplSplit()
    silent exec "!kitty @ launch --title Output --keep-focus xonsh"
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
    let command = '!kitty @ send-text --match title:Output ' . text
    return command
endfun


fun! SelectSection()
    set nowrapscan
    let line_before_search = line(".")
    silent! exec "?# %%"
    if line(".")!=line_before_search
        normal! j0v
    else
        normal! ggv
    endif
    let line_before_search = line(".")
    silent! exec "/# %%"
    if line(".")!=line_before_search
        normal! k$
    else
        normal! G
    endif
    set nowrapscan!
endfun


nnoremap <leader>sp :call ReplSplit()<cr>
nnoremap <cr> 0v$"xy:silent exec ParseRegister()<cr>:redraw!<cr>
vnoremap <cr> "xy:silent exec ParseRegister()<cr>:redraw!<cr>
nmap <leader><space> :call SelectSection()<cr><cr>

