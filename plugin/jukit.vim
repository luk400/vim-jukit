" TODO
"       - CHECK FOR EXISTENCE OF USER-DEFINED VARIABLES
"       - GNU LICENSE!

let g:wrapscan = &wrapscan
let g:plugin_path = jukit#GetPluginPath(expand("<sfile>"))
" User defined variables:

let g:pdf_viewer = "zathura"
let g:html_viewer = "firefox"
let g:python_cmd = "ipython"
let g:use_tcomment = 0
let g:inline_plotting_default = 1
let g:comment_marker_default = "#"
let g:highlight_markers = 1
let g:jukit_register = "x"
highlight seperation ctermbg=22 ctermfg=22


autocmd BufEnter * call jukit#InitBufVar()
if g:highlight_markers == 1
    sign define seperators linehl=seperation
    autocmd BufEnter,TextChangedI,TextChanged * exe "sign unplace * group=seperators buffer=" . bufnr()
    autocmd BufEnter,TextChangedI,TextChanged * call jukit#HighlightMarkers()
endif


" use the following command to execute a command in terminal before opening
" ipython. So if you want to start ipython in a virtual environment, you can
" simply use ':Ipython conda activate myvenv'
command! -nargs=1 KittyPy :call jukit#PythonSplit(<q-args>)
nnoremap <leader>py :call jukit#PythonSplit()<cr>
nnoremap <leader>sp :call jukit#ReplSplit()<cr>
nnoremap <cr> :call jukit#SendLine()<cr>
vnoremap <cr> :<C-U>call jukit#SendSelection()<cr>
nmap <leader><space> :call jukit#SendSection()<cr>
nnoremap <leader>cc :call jukit#SendUntilCurrentSection()<cr><c-o>
nnoremap <leader>all :call jukit#SendAll()<cr>
nnoremap <leader>mm :call jukit#NewMarker()<cr>

nnoremap <leader><leader>np :call jukit#NotebookConvert(1)<cr>
nnoremap <leader><leader>pn :call jukit#NotebookConvert(0)<cr>
nnoremap <leader>pdf :call jukit#SaveNBToFile(0,1,'pdf')<cr>
nnoremap <leader>rpdf :call jukit#SaveNBToFile(1,1,'pdf')<cr>
nnoremap <leader>html :call jukit#SaveNBToFile(0,1,'html')<cr>
nnoremap <leader>rhtml :call jukit#SaveNBToFile(1,1,'html')<cr>
