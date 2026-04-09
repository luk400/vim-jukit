" `s:markers_nlines` / `s:textcell_nlines` USED to live here as
" script-local cache variables for "did the buffer line count change
" since the last refresh?". They were script-local, so opening a new
" buffer with the same line count as the previous one would short-
" circuit the refresh and leave the new buffer un-highlighted. They are
" now buffer-local (`b:jukit_markers_nlines` / `b:jukit_textcell_nlines`)
" and initialized lazily on first use; see jukit#highlight_markers and
" jukit#place_markdown_cell_signs below.
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

    " IMPORTANT: `id` MUST be the line number (`v`), NOT the array index
    " (`l`). vim signs are keyed by (group, id, buffer), and
    " sign_placelist UPDATES an existing sign with the same key rather
    " than creating a new one. If we used `l` (which restarts at 0 for
    " every md cell in the buffer), the second cell's ids 0,1,2,...
    " would silently move the signs that the first cell just placed at
    " those same ids -- so cell 1's leading rows would lose their
    " background highlight while only the last cell would render
    " correctly. With `v` (the absolute line number), every line gets a
    " unique id and cells stop trampling each other.
    let lines = range(line('.'), num_end)
    let sign_list = map(lines, {l, v -> {
        \ 'buffer': bufnr('%', 1),
        \ 'group': 'jukit_textcells',
        \ 'name': 'jukit_textcells',
        \ 'id': v,
        \ 'lnum': v,
        \ 'priority': 1}})
    call sign_placelist(sign_list)
endfun

fun! s:highlight_sep_lines(val) abort
    call sign_place(a:val, 'jukit_cell_markers', 'jukit_cell_markers',
        \ bufnr('%', 1), {'lnum': a:val, 'priority': 2})
endfun

fun! jukit#place_markdown_cell_signs(force) abort
    " Buffer-local line-count cache. Was previously script-local
    " (s:textcell_nlines), which short-circuited the refresh whenever
    " you switched between two buffers that happened to share a line
    " count -- the new buffer's md backgrounds would never get placed.
    " b: scopes the cache per buffer so each gets its own first-call
    " refresh.
    if exists('b:jukit_textcell_nlines')
        \ && b:jukit_textcell_nlines == line('$') && !a:force
        return
    endif
    let b:jukit_textcell_nlines = line('$')

    let save_view = winsaveview()

    call sign_unplace('jukit_textcells', {'buffer': bufnr('%', 1)})

    silent exe 'g/' . s:md_start_pattern
        \ . "/call s:add_signs_in_region(search('" . s:md_end_pattern . "', 'n'))"

    call winrestview(save_view)
endfun

fun! jukit#highlight_markers(force) abort
    " Buffer-local line-count cache. See the comment in
    " jukit#place_markdown_cell_signs for why this used to live in a
    " script-local variable and why it was wrong.
    if exists('b:jukit_markers_nlines')
        \ && b:jukit_markers_nlines == line('$') && !a:force
        return
    endif
    let b:jukit_markers_nlines = line('$')

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
        let current_syntax = b:current_syntax
        unlet b:current_syntax
    endif

    if !hlexists('jukit_textcell_quotes')
        highlight jukit_textcell_quotes guifg=#212d3d ctermfg=Darkgrey
    endif

    if filereadable(g:jukit_text_syntax_file)
        exe 'syn include @markdown_cells ' . g:jukit_text_syntax_file
    endif

    if exists('current_syntax')
        let b:current_syntax = current_syntax
    endif

    syntax spell default

    exe 'syn match jukit_textcell_quotes /' . s:md_start_pattern . '\|' 
        \. s:md_end_pattern . '/ containedin=textcell'
    exe 'syn region textcell keepend start=/' . s:md_start_pattern . '/ end=/' 
        \. s:md_end_pattern . '/ contains=@markdown_cells containedin=ALL'
endfun
