"""""""""""""""""""
" Startup functions
fun! s:HighlightMarkers()
    " Highlights all cell markers in file
 
    call getline(1, '$')->map({l, v -> [l+1, v =~ "|%%--%%|"]})
        \->filter({k,v -> v[1]})->map({k,v -> v[0]})
        \->map({k,v -> s:HighlightSepLines(k,v)})
    return
endfun


fun! s:HighlightSepLines(key, val)
    " used by s:HighlightMarkers() to highlight markers
 
    exe "sign place 1 line=" . a:val . " group=cell_markers name=cell_markers buffer="
        \ . bufnr() | nohl
    return
endfun


"""""""""""""""""""
" Startup variables
let s:jukit_highlight_markers = get(g:, 'jukit_highlight_markers', 1)
let s:jukit_hl_settings = get(g:, 'jukit_hl_settings', 'ctermbg=22 ctermfg=22')
let s:jukit_mappings = get(g:, 'jukit_mappings', 1)


""""""""""""""
" Autocommands
if s:jukit_highlight_markers == 1
    exec 'highlight cell_markers ' . s:jukit_hl_settings
    sign define cell_markers linehl=cell_markers
    autocmd BufEnter,TextChangedI,TextChanged * exe
        \ "sign unplace * group=cell_markers buffer=" . bufnr()
    autocmd BufEnter,TextChangedI,TextChanged * call s:HighlightMarkers()
endif


""""""""""
" Mappings
if s:jukit_mappings == 1
    if !hasmapto('jukit#PythonSplit()', 'n')
        nnoremap <leader>py :call jukit#PythonSplit()<cr>
    endif
    if !hasmapto('jukit#ReplSplit()', 'n')
        nnoremap <leader>sp :call jukit#WindowSplit()<cr>
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
        nnoremap <leader>np :call jukit#NotebookConvert(1)<cr>
    endif
    if !hasmapto('jukit#NotebookConvert(0)', 'n')
        nnoremap <leader>pn :call jukit#NotebookConvert(0)<cr>
    endif
    if !hasmapto('jukit#SaveNBToFile(0,1,"html")', 'n')
        nnoremap <leader>ht :call jukit#SaveNBToFile(0,1,'html')<cr>
    endif
    if !hasmapto('jukit#SaveNBToFile(1,1,"html")', 'n')
        nnoremap <leader>rht :call jukit#SaveNBToFile(1,1,'html')<cr>
    endif
endif

" use the following to execute a command in terminal before opening python
" shell (e.g. conda activate myenv)
command! -nargs=1 JukitPy :call jukit#PythonSplit(<q-args>)
