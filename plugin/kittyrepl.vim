
fun! ReplSplit()
    silent exec "!kitty @ launch --title Output --keep-focus xonsh"
endfun

fun! SendLine()
    normal! 0v$"xy

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
    silent! exec command
    redraw!
endfun

nnoremap <leader>sp :call ReplSplit()<cr>
nnoremap <leader>send :call SendLine()<cr>

