let s:markers_nlines = -1
let s:textcell_nlines = -1
let s:md_start_pattern = '.*' . g:_jukit_md_mark . '$'
let s:md_end_pattern = '^' . g:_jukit_md_mark . '.*'

"""""""""""""""""""""""""""""""
" check consistency of cell ids
fun! s:comp_func(v1, v2) abort
    if a:v1 == a:v2
        call add(s:duplicates, a:v1)
        return 0
    else
        return 1
    endif
endfun

fun! s:replace_marker(id1, id2, lnum) abort
    let id1 = a:id1 != -1 ? a:id1 : jukit#util#get_unique_id()
    let id2 = a:id2 != -1 ? a:id2 : jukit#util#get_unique_id()
    let lnum = a:lnum != -1 ? a:lnum : line('.')-1

    if g:jukit_use_tcomment == 1
        call setline(lnum, '|%%--%%| <' . id1 . '|' . id2 . '>')
        try
            call tcomment#Comment(lnum, lnum)
        catch
            call setline(lnum, g:jukit_comment_mark . '|%%--%%| <' . id1 . '|' . id2 . '>')
            echom '[vim-jukit] tcomment#Comment could not be executed, using '
                \. 'g:jukit_comment_mark...'
        endtry
    else
        call setline(lnum, g:jukit_comment_mark . '|%%--%%| <' . id1 . '|' . id2 . '>')
    endif

    return [id1, id2]
endfun

fun! s:fix_duplicate_ids(ids) abort
    let save_view = winsaveview()
    let bnr = bufnr('%', 1)
    echom '[vim-jukit] Duplicate cell_ids detected: ' . join(uniq(a:ids), ', ')
    for id in a:ids
        call cursor(1,1)
        let lnum = search('|' . id . '>')

        if !lnum
            continue
        endif

        echom '[vim-jukit] Replacing first found occurence of id ' . id
            \. ' in line ' . lnum
        let id1 = jukit#util#get_marker_below()['ids'][0]
        call s:replace_marker(id1, -1, lnum)
        break
    endfor
    call winrestview(save_view)
endfun

fun! s:rename_first_cell() abort
    let save_view = winsaveview()
    call cursor(1,1)
    let ids_below = jukit#util#get_marker_below()
    call s:replace_marker(-1, ids_below['ids'][1], ids_below['pos'])
    call winrestview(save_view)
endfun

fun! s:fix_pos(i, ids) abort
    call add(s:fix_pos, '{' . a:ids['pos'][a:i] . ';' . a:ids['pos'][a:i+1] . '}')
    let id = matchstr(getline(a:ids['pos'][a:i]), '|%%--%%|.*<.*|\zs.*\ze>')
    let fixed = substitute(getline(a:ids['pos'][a:i+1]), '|%%--%%|.*<\zs.*\ze|.*>', id, 'g')
    call setline(a:ids['pos'][a:i+1], fixed)
endfun

fun! jukit#check_ids() abort
    if !g:jukit_save_output
        return
    endif

    let ids = jukit#util#get_all_ids()
    let ids2_unique = len(uniq(sort(copy(ids[2])))) == len(ids[2])
    let ids1_unique = len(uniq(sort(copy(ids[1])))) == len(ids[1])
    let is_consistent = ids[1][1:]==ids[2][:-2] && ids1_unique && ids2_unique

    if is_consistent
        return
    elseif !ids2_unique
        let s:duplicates = []
        call uniq(sort(copy(ids[2])), function('s:comp_func'))
        call s:fix_duplicate_ids(s:duplicates)
    endif

    let s:fix_pos = []
    let idx_fix = filter(range(len(ids[1])-1), {k,v -> ids[1][v+1] != ids[2][v]})
    call map(idx_fix, {k,v -> s:fix_pos(v, ids)})

    if len(s:fix_pos)
        echom '[vim-jukit] Inconsistent cell-ids corrected in lines: ' . join(s:fix_pos, ', ')
    endif

    let ids = jukit#util#get_all_ids()
    let ids1_unique = len(uniq(sort(copy(ids[1])))) == len(ids[1])
    if !ids1_unique
        call s:rename_first_cell()
    endif
    echom "[vim-jukit] -> Try to use jukit-functions to create/delete/modify cells!"
        \. "Otherwise saved output may be assigned to unexpected cell-ids!"
endfun

""""""""""""""
" highlighting
fun! s:add_signs_in_region(lnum_end) abort
    if line('.')>a:lnum_end
        let num_end = line('$')
    else
        let num_end = a:lnum_end
    endif

    let lines = range(line('.'), num_end)
    let sign_list = map(lines, {l, v -> {
        \ 'buffer': bufnr('%', 1), 
        \ 'group': 'jukit_textcells', 
        \ 'name': 'jukit_textcells', 
        \ 'id': l, 
        \ 'lnum': v,
        \ 'priority': 1}})
    call sign_placelist(sign_list)
endfun

fun! s:highlight_sep_lines(val) abort
    call sign_place(a:val, 'jukit_cell_markers', 'jukit_cell_markers',
        \ bufnr('%', 1), {'lnum': a:val, 'priority': 2})
endfun

fun! jukit#place_markdown_cell_signs(force) abort
    if line('$') == s:textcell_nlines && !a:force
        return
    endif
    let s:textcell_nlines = line('$')

    let save_view = winsaveview()

    call sign_unplace('jukit_textcells', {'buffer': bufnr('%', 1)})

    silent exe 'g/' . s:md_start_pattern
        \ . "/call s:add_signs_in_region(search('" . s:md_end_pattern . "', 'n'))"

    call winrestview(save_view)
endfun

fun! jukit#highlight_markers(force) abort
    if line('$') == s:markers_nlines && !a:force
        return
    endif
    let s:markers_nlines = line('$')

    call sign_unplace('jukit_cell_markers', {'buffer': bufnr('%', 1)})
    let lines = getline(1, '$')
    call map(lines, {l, v -> v =~ '|%%--%%|' ? s:highlight_sep_lines(l+1) : 0})
endfun

fun! jukit#highlighting_setup(aupat) abort
    if !filereadable(g:jukit_text_syntax_file)
        echom "[vim-jukit] Given syntax_file (`g:jukit_text_syntax_file='"
            \ . g:jukit_text_syntax_file . "'`) not found. Make sure to specify absolute path!"
    endif

    if g:jukit_enable_textcell_syntax
        exe 'autocmd BufNewFile,BufReadPost ' . a:aupat . ' call s:textcell_syn_match()'
    endif

    if g:jukit_highlight_markers
        if !hlexists('jukit_cellmarker_colors')
            highlight jukit_cellmarker_colors guifg=#1d615a guibg=#1d615a ctermbg=22 ctermfg=22
        endif

        sign define jukit_cell_markers linehl=jukit_cellmarker_colors
        exe 'autocmd BufEnter,TextChangedI,TextChanged ' . a:aupat
            \ . ' call jukit#highlight_markers(0)'
    endif

    if g:jukit_enable_textcell_bg_hl
        if !hlexists('jukit_textcell_bg_colors')
            highlight jukit_textcell_bg_colors guibg=#131628 ctermbg=16
        endif

        sign define jukit_textcells linehl=jukit_textcell_bg_colors
        exe 'autocmd BufEnter,TextChangedI,TextChanged ' . a:aupat
            \ . ' call jukit#place_markdown_cell_signs(0)'
    endif
endfun

fun! s:textcell_syn_match() abort
    if exists('b:current_syntax')
        unlet b:current_syntax
    endif

    if !hlexists('jukit_textcell_quotes')
        highlight jukit_textcell_quotes guifg=#212d3d ctermfg=Darkgrey
    endif

    if filereadable(g:jukit_text_syntax_file)
        exe 'syn include @markdown_cells ' . g:jukit_text_syntax_file
    endif

    exe 'syn match jukit_textcell_quotes /' . s:md_start_pattern . '\|' 
        \. s:md_end_pattern . '/ containedin=textcell'
    exe 'syn region textcell keepend start=/' . s:md_start_pattern . '/ end=/' 
        \. s:md_end_pattern . '/ contains=@markdown_cells containedin=ALL'
endfun


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" make users of old vim-jukit version aware of breaking changes in new version
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:msg = "[vim-jukit] Trying to use a deprecated function. Please visit https://github.com/luk400/vim-jukit to read about the new vim-jukit release!"
fun! jukit#PythonSplit()
    echom s:msg
endfun
fun! jukit#WindowSplit()
    echom s:msg
endfun
fun! jukit#SendLine()
    echom s:msg
endfun
fun! jukit#SendSelection()
    echom s:msg
endfun
fun! jukit#SendSection()
    echom s:msg
endfun
fun! jukit#SendUntilCurrentSection()
    echom s:msg
endfun
fun! jukit#SendAll()
    echom s:msg
endfun
fun! jukit#NewMarker()
    echom s:msg
endfun
fun! jukit#NotebookConvert()
    echom s:msg
endfun
fun! jukit#SaveNBToFile(arg1, arg2, arg3)
    echom s:msg
endfun
fun! jukit#SaveNBToFile(arg1, arg2, arg3)
    echom s:msg
endfun
fun! jukit#SaveNBToFile(arg1, arg2, arg3)
    echom s:msg
endfun
fun! jukit#SaveNBToFile(arg1, arg2, arg3)
    echom s:msg
endfun
fun! jukit#PythonHelp()
    echom s:msg
endfun
