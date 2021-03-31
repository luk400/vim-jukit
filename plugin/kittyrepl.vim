" TODO
"       - RENAME PLUGIN TO VIM-JUKIT
"       - CHECK FOR EXISTENCE OF USER-DEFINED VARIABLES
"       - COMMENT FUNCTIONS
"       - GNU LICENSE!
"       - MAKE USED REGISTER CHOOSABLE BY USER (DEFAULT 'x')

let g:wrapscan = &wrapscan
let g:plugin_path = kittyrepl#GetPluginPath(expand("<sfile>"))
" User defined variables:
let g:pdf_viewer = "zathura"
let g:html_viewer = "firefox"
let g:python_cmd = 'ipython'
let g:use_tcomment = 0
let g:inline_plotting_default = 1
let g:comment_marker_default = "#"
let g:highlight_markers = 1
highlight seperation ctermbg=22 ctermfg=22


autocmd BufEnter * call kittyrepl#InitBufVar()
if g:highlight_markers == 1
    sign define seperators linehl=seperation
    autocmd BufEnter,TextChangedI,TextChanged * exe "sign unplace * group=seperators buffer=" . bufnr()
    autocmd BufEnter,TextChangedI,TextChanged * call kittyrepl#HighlightMarkers()
endif


" use the following command to execute a command in terminal before opening
" ipython. So if you want to start ipython in a virtual environment, you can
" simply use ':Ipython conda activate myvenv'
command! -nargs=1 KittyPy :call kittyrepl#PythonSplit(<q-args>)
nnoremap <leader>py :call kittyrepl#PythonSplit()<cr>
nnoremap <leader>sp :call kittyrepl#ReplSplit()<cr>
nnoremap <cr> :call kittyrepl#SendLine()<cr>
vnoremap <cr> :<C-U>call kittyrepl#SendSelection()<cr>
nmap <leader><space> :call kittyrepl#SendSection()<cr>
nnoremap <leader>cc :call kittyrepl#SendUntilCurrentSection()<cr><c-o>
nnoremap <leader>all :call kittyrepl#SendAll()<cr>
nnoremap <leader>mm :call kittyrepl#NewMarker()<cr>

nnoremap <leader><leader>np :call kittyrepl#NotebookConvert(1)<cr>
nnoremap <leader><leader>pn :call kittyrepl#NotebookConvert(0)<cr>
nnoremap <leader>pdf :call kittyrepl#SaveNBToFile(0,1,'pdf')<cr>
nnoremap <leader>rpdf :call kittyrepl#SaveNBToFile(1,1,'pdf')<cr>
nnoremap <leader>html :call kittyrepl#SaveNBToFile(0,1,'html')<cr>
nnoremap <leader>rhtml :call kittyrepl#SaveNBToFile(1,1,'html')<cr>
