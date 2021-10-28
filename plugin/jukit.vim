""""""""""""""""""""""""""""""""""""""""""""""
" Functions used in Autocmd's for highlighting
fun! s:HighlightMarkers()
    exe "sign unplace * group=JukitCellMarkers buffer=" . bufnr()
    " Highlights all cell markers in file
 
    " get content of lines
    let lines = getline(1, '$')
    " the following results in a list of sublists (one for each line), where 
    " each sublist contains 2 numbers: 
    " first is the line number, second indicates if it contains marker or not
    let has_marker = map(lines, {l, v -> [l+1, v =~ "|%%--%%|"]})
    " filter out sublists containing cell markers
    let marker_sublists = filter(has_marker, {k,v -> v[1]})
    " get position from each sublist
    let pos = map(marker_sublists, {k,v -> v[0]})
    " highlight lines
    call map(pos, {k,v -> s:HighlightSepLines(k,v)})
endfun

fun! s:HighlightSepLines(key, val)
    " used by s:HighlightMarkers() to highlight markers
    exe "sign place 1 line=" . a:val . " group=JukitCellMarkers name=JukitCellMarkers buffer="
      \ . bufnr() | nohl
endfun

fun! s:AddSignsInRegion()
  let num_lines_file = line('$')
  let end_of_file = 0
  let i = 0
  while !((line('.')+i)==line('$'))
      if !(getline(line('.')+i)=~'|%%--%%|')
          exe "sign place 1 line=" . (line('.')+i) . " group=JukitTextcellColors "
            \ . "name=JukitTextcellColors buffer=" . bufnr()
          let i += 1
      else
          return
      endif
  endwhile
endfun

fun! s:LineNrChange()
  let num_lines = line('$')
  if b:jukit_total_linenr > num_lines
    let b:jukit_total_linenr = num_lines
    return 1
  elseif b:jukit_total_linenr < num_lines
    let b:jukit_total_linenr = num_lines
    return -1
  endif
  return 0
endfun

fun! s:PlaceMarkdownCellSigns(textcell_regex)
  if !exists('b:jukit_total_linenr')
    let b:jukit_total_linenr=-1
  endif

  let nr_lines_change = s:LineNrChange()
  if nr_lines_change!=0
    if nr_lines_change < 0 
      exe "sign unplace * group=TextCellRegion buffer=" . bufnr()
    endif
    let save_view = winsaveview()
    " first unplace existing signs
    silent! exe "sign unplace * group=TextCellRegion buffer=" . bufnr()
    " Then add signs again
    silent! exe 'g/' . a:textcell_regex . '/call s:AddSignsInRegion()'
    call winrestview(save_view)
  endif
endfun

fun! s:LoadMainSyntaxFile(filepath)
  if filereadable(a:filepath)
    unlet! b:current_syntax
    exe 'syn include @NativeSyn ' . a:filepath
  endif
endfun

"""""""""""""""""""
" Startup variables
let s:jukit_highlight_markers = get(g:, 'jukit_highlight_markers', 1)
let s:jukit_mappings = get(g:, 'jukit_mappings', 1)
let s:jukit_enable_textcell_hl = get(g:, 'jukit_enable_textcell_hl', 1)
let s:jukit_enable_text_syntax_hl = get(g:, 'jukit_enable_text_syntax_hl', 1)
let s:jukit_text_syntax_file_dir = get(g:, 'jukit_text_syntax_file_dir', $VIMRUNTIME . '/syntax/')
let s:jukit_text_syntax_file = get(g:, 'jukit_text_syntax_file', 'markdown.vim')

""""""""""""""
" highlighting

" The s:textcell_regex identifies text cells for highlighting and syntax.
" \(|%%--%%|\n\)\@<=\n*""" searches for """ preceeded by some newline
" characters which follow a cell marker (cell markers are not matched since
" they are in lookbehind).
" the expression \(^\%(.*|%%--%%|\)\@!.*\n\) will match all lines where the
" cell marker |%%--%%| is not contained (more precisely it will match all
" characters followed by a newline character - i.e. .*\n - if there was no
" cell marker in the line - i.e. ^\%(.*|%%--%%|\)\@!)
" lastly, """\n*\(.\{2,4}|%%--%%|\)\@= will search for """ followed by one
" or multiple newlines after which a cell marker occurs (which is again not
" matched since it's in a lookahead)
let s:textcell_regex = '\(|%%--%%|\n\)\@<=\n*"""\n\(^\%(.*|%%--%%|\)\@!.*\n\)*"""\n*\(.\{1,4}|%%--%%|\)\@='

if s:jukit_highlight_markers
  if !hlexists('JukitCellMarkers')
    highlight JukitCellMarkers guifg=#1d615a guibg=#1d615a ctermbg=22 ctermfg=22
  endif

  sign define JukitCellMarkers linehl=JukitCellMarkers
  autocmd BufEnter,InsertLeave,TextChanged * call s:HighlightMarkers()
endif

if s:jukit_enable_textcell_hl
  if !hlexists('JukitTextcellColors')
    highlight JukitTextcellColors guibg=#131628 ctermbg=0
  endif

  sign define JukitTextcellColors linehl=JukitTextcellColors
  autocmd BufEnter,TextChangedI,TextChanged * call s:PlaceMarkdownCellSigns(s:textcell_regex)
endif

if s:jukit_enable_text_syntax_hl
  au BufEnter * syn clear

  if type(s:jukit_text_syntax_file)==v:t_string
    let s:jukit_text_syntax_file = [s:jukit_text_syntax_file]
  endif
 
  au BufEnter * exe 'syn match textcell /' . s:textcell_regex . '/ contains=@MarkdownCells'
  for syntax_file in s:jukit_text_syntax_file
    au BufEnter * exe 'syn include @MarkdownCells ' . s:jukit_text_syntax_file_dir . syntax_file
  endfor
 
  let s:main_syntax_dir = $VIMRUNTIME . '/syntax/'
  au BufEnter * exe 'syn match codecell /\(' . s:textcell_regex . '\)\@!/ contains=@NativeSyn'
  au BufEnter * call s:LoadMainSyntaxFile(s:main_syntax_dir . &filetype . '.vim')

  " prevent buggy syntax matching
  au BufEnter * syntax sync fromstart
endif

""""""""""
" Mappings
if s:jukit_mappings == 1
    if !hasmapto('jukit#PythonSplit()', 'n')
        nnoremap <leader>py :call jukit#PythonSplit()<cr>
    endif
    if !hasmapto('jukit#WindowSplit()', 'n')
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
    if !hasmapto('jukit#NotebookConvert()', 'n')
        nnoremap <leader>np :call jukit#NotebookConvert()<cr>
    endif
    if !hasmapto("jukit#SaveNBToFile(0,1,'html')", 'n')
        nnoremap <leader>ht :call jukit#SaveNBToFile(0,1,'html')<cr>
    endif
    if !hasmapto("jukit#SaveNBToFile(1,1,'html')", 'n')
        nnoremap <leader>rht :call jukit#SaveNBToFile(1,1,'html')<cr>
    endif
    if !hasmapto("jukit#SaveNBToFile(0,1,'pdf')", 'n')
        nnoremap <leader>pd :call jukit#SaveNBToFile(0,1,'pdf')<cr>
    endif
    if !hasmapto("jukit#SaveNBToFile(1,1,'pdf')", 'n')
        nnoremap <leader>rpd :call jukit#SaveNBToFile(1,1,'pdf')<cr>
    endif
    if !hasmapto('jukit#PythonHelp()', 'v')
        vnoremap <leader>h :<C-U>call jukit#PythonHelp()<cr>
    endif
endif

" use the following to execute a command in terminal before opening python
" shell (e.g. conda activate myenv)
command! -nargs=1 JukitPy :call jukit#PythonSplit(<q-args>)
