autocmd BufEnter * call jukit#InitBufVar()


let s:highlight_markers = get(g:, 'highlight_markers', 1)
if s:highlight_markers == 1
    let s:jukit_hl_settings = get(g:, 'jukit_hl_settings', 'ctermbg=22 ctermfg=22')
    exec 'highlight cell_markers ' . s:jukit_hl_settings
    sign define cell_markers linehl=cell_markers
    autocmd BufEnter,TextChangedI,TextChanged * exe
        \ "sign unplace * group=cell_markers buffer=" . bufnr()
    autocmd BufEnter,TextChangedI,TextChanged * call jukit#HighlightMarkers()
endif


if !exists("g:jukit_no_mappings") || !g:jukit_no_mappings
    if !hasmapto('jukit#PythonSplit()', 'n')
        nnoremap <leader>py :call jukit#PythonSplit()<cr>
    endif
    if !hasmapto('jukit#ReplSplit()', 'n')
        nnoremap <leader>sp :call jukit#ReplSplit()<cr>
    endif
    if !hasmapto('jukit#SendLine()', 'n')
        nnoremap <cr> :call jukit#SendLine()<cr>
    endif
    if !hasmapto('jukit#SendSelection()', 'v')
        vnoremap <cr> :<C-U>call jukit#SendSelection()<cr>
    endif
    if !hasmapto('jukit#SendSection()', 'n')
        nnoremap <leader><space> :call jukit#SendSection()<cr>
    endif
    if !hasmapto('jukit#SendUntilCurrentSection()', 'n')
        nnoremap <leader>cc :call jukit#SendUntilCurrentSection()<cr><c-o>
    endif
    if !hasmapto('jukit#SendAll()', 'n')
        nnoremap <leader>all :call jukit#SendAll()<cr>
    endif
    if !hasmapto('jukit#NewMarker()', 'n')
        nnoremap <leader>mm :call jukit#NewMarker()<cr>
    endif
    if !hasmapto('jukit#NotebookConvert(1)', 'n')
        nnoremap <leader><leader>np :call jukit#NotebookConvert(1)<cr>
    endif
    if !hasmapto('jukit#NotebookConvert(0)', 'n')
        nnoremap <leader><leader>pn :call jukit#NotebookConvert(0)<cr>
    endif
    if !hasmapto('jukit#SaveNBToFile(0,1,"pdf")', 'n')
        nnoremap <leader>pdf :call jukit#SaveNBToFile(0,1,'pdf')<cr>
    endif
    if !hasmapto('jukit#SaveNBToFile(1,1,"pdf")', 'n')
        nnoremap <leader>rpdf :call jukit#SaveNBToFile(1,1,'pdf')<cr>
    endif
    if !hasmapto('jukit#SaveNBToFile(0,1,"html")', 'n')
        nnoremap <leader>html :call jukit#SaveNBToFile(0,1,'html')<cr>
    endif
    if !hasmapto('jukit#SaveNBToFile(1,1,"html")', 'n')
        nnoremap <leader>rhtml :call jukit#SaveNBToFile(1,1,'html')<cr>
    endif
endif


" use the following command to execute a command in terminal before opening
" ipython. So if you want to start ipython in a virtual environment, you can
" simply use ':Ipython conda activate myvenv'
command! -nargs=1 KittyPy :call jukit#PythonSplit(<q-args>)
