
fun! ReplSplit()
    silent exec "!kitty @ launch --title Output --keep-focus xonsh"
endfun

fun! ParseRegister()
python3 << EOF
import vim 
import json

reg = vim.eval("@x") 
escaped = reg.translate(str.maketrans({
    "\n": "\\\n",
    "\\": "\\\\",
    '"': '\\"',
    "'": "\\'",
    "#": "\\#",
    "!": "\!",
    }))
 
vim.command("let text = shellescape({})".format(json.dumps(escaped)))
EOF
    let command = '!kitty @ send-text --match title:Output ' . text
    return command
endfun

nnoremap <leader>sp :call ReplSplit()<cr>
nnoremap <cr> 0v$"xy:silent exec ParseRegister()<cr>:redraw!<cr>
vnoremap <cr> "xy:silent exec ParseRegister()<cr>:redraw!<cr>

