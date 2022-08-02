call jukit#util#md_buffer_vars()
let s:jukit_textcell_regex = b:jukit_md_start . '\_.{-}' . b:jukit_md_end

fun! s:copy_output(from_id, to_id) abort
python3 << EOF
import vim, os, sys
sys.path.append(vim.eval('jukit#util#plugin_path() . g:_jukit_ps . "helpers"'))
from ipynb_convert import util

from_id = vim.eval('a:from_id')
to_id = vim.eval('a:to_id')

fname = vim.eval("expand('%:p')")
dir_, f = os.path.split(fname)
outhist_file = os.path.join(dir_, '.jukit', f'{os.path.splitext(f)[0]}_outhist.json')

util.copy_output(from_id, to_id, outhist_file)
EOF
endfun

fun! s:merge_outputs(cell_above, cell_below, new_id) abort
python3 << EOF
import vim, os, sys
sys.path.append(vim.eval('jukit#util#plugin_path() . g:_jukit_ps . "helpers"'))
from ipynb_convert import util

cell_above = vim.eval('a:cell_above')
cell_below = vim.eval('a:cell_below')
new_id = vim.eval('a:new_id')

fname = vim.eval("expand('%:p')")
dir_, f = os.path.split(fname)
outhist_file = os.path.join(dir_, '.jukit', f'{os.path.splitext(f)[0]}_outhist.json')

util.merge_outputs(outhist_file, cell_above, cell_below, new_id)
EOF
endfun

fun! s:delete_output(cell_id) abort
python3 << EOF
import vim, os, sys
sys.path.append(vim.eval('jukit#util#plugin_path() . g:_jukit_ps . "helpers"'))
from ipynb_convert import util

cell_id = vim.eval('a:cell_id')

fname = vim.eval("expand('%:p')")
dir_, f = os.path.split(fname)
outhist_file = os.path.join(dir_, '.jukit', f'{os.path.splitext(f)[0]}_outhist.json')

util.delete_cell_output(outhist_file, cell_id)
EOF
endfun

fun! s:new_marker(id1, id2, lnum) abort
    let id1 = a:id1 != -1 ? a:id1 : jukit#util#get_unique_id()
    let id2 = a:id2 != -1 ? a:id2 : jukit#util#get_unique_id()
    let lnum = a:lnum != -1 ? a:lnum : line('.')-1
    
    if g:jukit_use_tcomment == 1
        call append(lnum, '|%%--%%| <' . id1 . '|' . id2 . '>')
        try
            call tcomment#Comment(lnum+1, lnum+1)
        catch
            call setline(lnum+1, g:jukit_comment_mark . '|%%--%%| <' . id1 . '|' . id2 . '>')
            echom '[vim-jukit] tcomment#Comment could not be executed, using '
                \. 'g:jukit_comment_mark...'
        endtry
    else
        call append(lnum, g:jukit_comment_mark . '|%%--%%| <' . id1 . '|' . id2 . '>')
    endif

    return [id1, id2]
endfun

fun! s:set_marker_above(id1, id2) abort
    let marker_pos_above = search('|%%--%%|', 'nbW')
    if marker_pos_above
        let line = getline(marker_pos_above)
        if a:id1 != -1
            let line = substitute(line, '|%%--%%|.*<\zs.*\ze|.*>', a:id1, 'g')
        endif

        if a:id2 != -1
            let line = substitute(line, '|%%--%%|.*<.*|\zs.*\ze>', a:id2, 'g')
        endif
        call setline(marker_pos_above, line)
    endif
endfun

fun! s:set_marker_below(id1, id2) abort
    let marker_pos_below = search('|%%--%%|', 'nW')
    if marker_pos_below
        let line = getline(marker_pos_below)
        if a:id1 != -1
            let line = substitute(line, '|%%--%%|.*<\zs.*\ze|.*>', a:id1, 'g')
        endif

        if a:id2 != -1
            let line = substitute(line, '|%%--%%|.*<.*|\zs.*\ze>', a:id2, 'g')
        endif
        call setline(marker_pos_below, line)
    endif
endfun

fun! jukit#cells#delete_outputs(all) abort
    if a:all
        call s:delete_output(v:null)
    else
        call s:delete_output(jukit#util#get_current_cell_id())
    endif
    if jukit#splits#split_exists('outhist')
        call jukit#splits#show_last_cell_output(1)
    endif
endfun

fun! jukit#cells#split() abort
    " affected cell markers: above and below
    " assign new cell id to: current cell, new cell
    " effect on output: assign output to current cell
    
    call jukit#util#md_buffer_vars()
    let markers = jukit#util#get_adjacent_markers()
    let new_id_above = jukit#util#get_unique_id()
    let cell_id = jukit#util#get_unique_id()

    if !markers['above']['pos'] && !markers['below']['pos']
        call s:copy_output('NONE', new_id_above)
    elseif markers['above']['pos']
        call s:copy_output(markers['above']['ids'][1], new_id_above)
    elseif markers['below']['pos']
        call s:copy_output(markers['below']['ids'][0], new_id_above)
    endif

    if markers['above']['pos']
        call s:set_marker_above(-1, new_id_above)
    endif

    if markers['below']['pos']
        call s:set_marker_below(cell_id, -1)
    endif

    let save_view = winsaveview()
    call cursor(line('.')+1, '$')
    let md_cur = search(b:jukit_md_start, 'nbW') > markers['above']['pos']
    call winrestview(save_view)

    call s:new_marker(new_id_above, cell_id, line('.')-1)

    if md_cur
        call append(line('.')-2, b:jukit_md_end)
        call append(line('.')-1, b:jukit_md_start)
    endif
endfun

fun! jukit#cells#merge_below() abort
    " affected cell markers: above, next but one below
    " assign new cell id to: current cell (i.e. merged cell)
    " effect on output: merge outputs and assign to merged cell

    call jukit#util#md_buffer_vars()
    let markers = jukit#util#get_adjacent_markers()
    let save_view = winsaveview()
    if !markers['below']['pos']
        echom "[vim-jukit] No cell below!"
        return
    endif
    call cursor(markers['below']['pos'], 1)
    let quotes_start_prev = search(b:jukit_md_start, 'nbW')
    let quotes_start_next = search(b:jukit_md_start, 'nW')
    call cursor(markers['below']['pos'] + 1, 1)
    let marker_pos_next_but_one = search('|%%--%%|', 'nW')

    if !marker_pos_next_but_one
        let marker_pos_next_but_one = line('$')
    endif

    let md_cur = quotes_start_prev > markers['above']['pos']
    let md_next = quotes_start_next < marker_pos_next_but_one && quotes_start_next

    if md_cur != md_next
        echom "[vim-jukit] Can only merge cells with the same type!"
        call winrestview(save_view)
        return
    endif

    if md_cur
        call cursor(markers['below']['pos'], 1)
        let quotes_end_cur = search(b:jukit_md_end, 'nbW')

        call deletebufline(bufnr('%'), quotes_end_cur, quotes_start_next)
    else
        call deletebufline(bufnr('%'), markers['below']['pos'])
    endif

    call winrestview(save_view)
    let cell_id = jukit#util#get_unique_id()
    call s:merge_outputs(markers['below']['ids'][0], markers['below']['ids'][1], cell_id)
    call s:set_marker_below(cell_id, -1)
    call s:set_marker_above(-1, cell_id)
endfun

fun! jukit#cells#merge_above() abort
    " affected cell markers: below, next but one above
    " assign new cell id to: current cell (i.e. merged cell)
    " effect on output: merge outputs and assign to merged cell

    call jukit#util#md_buffer_vars()
    let markers = jukit#util#get_adjacent_markers()
    let save_view = winsaveview()
    if !markers['above']['pos']
        echom "[vim-jukit] No cell above!"
        return
    endif
    call cursor(markers['above']['pos'], 1)
    let marker_pos_next = search('|%%--%%|', 'nbW')
    let quotes_start_next = search(b:jukit_md_start, 'nbW')
    let quotes_start_prev = search(b:jukit_md_start, 'nW')

    if !markers['below']['pos']
        let markers['below']['pos'] = line('$')
    endif

    let md_cur = quotes_start_prev < markers['below']['pos'] && quotes_start_prev
    let md_next = quotes_start_next > marker_pos_next

    if md_cur != md_next
        echom "[vim-jukit] Can only merge cells with the same type!"
        call winrestview(save_view)
        return
    endif

    let delete_id = matchstr(getline(markers['above']['pos']), '|%%--%%|.*<\zs\(.*\)\ze>')
    if md_cur
        call cursor(markers['above']['pos'], 1)
        let quotes_end_next = search(b:jukit_md_end, 'nbW')

        call winrestview(save_view)
        call deletebufline(bufnr('%'), quotes_end_next, quotes_start_prev)
    else
        call winrestview(save_view)
        call deletebufline(bufnr('%'), markers['above']['pos'])
    endif

    let cell_id = jukit#util#get_unique_id()
    call s:merge_outputs(markers['above']['ids'][0], markers['above']['ids'][1], cell_id)
    call s:set_marker_below(cell_id, -1)
    call s:set_marker_above(-1, cell_id)
endfun

fun! jukit#cells#create_below(markdown) abort
    " affected cell markers: above, below
    " assign new cell id to: new cell
    " effect on output: -

    let markers = jukit#util#get_adjacent_markers()
    let cell_id = jukit#util#get_unique_id()

    if markers['below']['pos']
        call s:set_marker_below(cell_id, -1)
        let pos = markers['below']['pos']
        call append(pos-1, ['', '', ''])
        call s:new_marker(markers['below']['ids'][0], cell_id, pos-1)
        call cursor(pos+2, 1)
    elseif markers['above']['pos']
        call append(line('$'), ['', '', ''])
        call s:new_marker(markers['above']['ids'][1], cell_id, line('$')-3)
        call cursor(line('$')-1, 1)
    else
        call append(line('$'), ['', '', ''])
        let ids = s:new_marker(-1, cell_id, line('$')-3)
        call s:copy_output('NONE', ids[0])
        call cursor(line('$')-1, 1)
    endif

    if a:markdown
        call jukit#util#md_buffer_vars()
        call setline(line('.')-1, b:jukit_md_start)
        call setline(line('.')+1, b:jukit_md_end)
    endif

    if g:jukit_highlight_markers
        call jukit#highlight_markers(1)
    endif
    if g:jukit_enable_textcell_bg_hl
        call jukit#place_markdown_cell_signs(1)
    endif
    startinsert
endfun

fun! jukit#cells#create_above(markdown) abort
    " affected cell markers: above, below
    " assign new cell id to: new cell
    " effect on output: -

    let markers = jukit#util#get_adjacent_markers()
    let cell_id = jukit#util#get_unique_id()

    if markers['above']['pos'] != 0
        call s:set_marker_above(cell_id, -1)
        let pos = markers['above']['pos']
        call append(pos-1, ['', '', ''])
        call s:new_marker(markers['above']['ids'][0], cell_id, pos-1)
        call cursor(pos+2, 1)
    elseif markers['below']['pos'] != 0
        call append(0, ['', '', ''])
        call s:new_marker(cell_id, markers['below']['ids'][0], 3)
        call cursor(2, 1)
    else
        call append(0, ['', '', ''])
        let ids = s:new_marker(cell_id, -1, 3)
        call s:copy_output('NONE', ids[1])
        call cursor(2, 1)
    endif

    if a:markdown
        call jukit#util#md_buffer_vars()
        call setline(line('.')-1, b:jukit_md_start)
        call setline(line('.')+1, b:jukit_md_end)
    endif

    if g:jukit_highlight_markers
        call jukit#highlight_markers(1)
    endif
    if g:jukit_enable_textcell_bg_hl
        call jukit#place_markdown_cell_signs(1)
    endif
    startinsert
endfun

fun! jukit#cells#delete() abort
    " affected cell markers: below, next but one above
    " assign new cell id to: -
    " effect on output: -

    let markers = jukit#util#get_adjacent_markers()

    if markers['below']['pos'] == 0
        let pos2 = line('$')
    else
        let pos2 = markers['below']['pos']-1
    endif

    if markers['above']['pos'] == 0
        let pos1 = 1
        let pos2 += 1
    else
        let pos1 = markers['above']['pos']
    endif

    call deletebufline(bufnr('%'), pos1, pos2)
    if markers['above']['pos'] && markers['below']['pos']
        call s:set_marker_below(markers['above']['ids'][0], -1)
    endif
    call cursor(line('.')+1, 1)
endfun

fun! jukit#cells#move_up() abort
    " affected cell markers: below, above, next but one above
    " assign new cell id to: -
    " effect on output: -
    
    let markers = jukit#util#get_adjacent_markers()
    if !markers['above']['pos']
        echom '[vim-jukit] No cell above!'
        return
    endif

    let marker_pos_current = markers['above']['pos']
    let id_cur = markers['above']['ids'][1]
    let marker_pos_other = search('|%%--%%|\(.*<' 
        \. join(markers['above']['ids'], '|') . '>\)\@!', 'nbW')
    let p1_other = marker_pos_other + 1
    let p2_other = markers['above']['pos'] - 1

    if !markers['below']['pos']
        let p2 = line('$')
    else
        let p2 = markers['below']['pos'] - 1
    endif
    let p1 = markers['above']['pos'] + 1

    let cpos = getpos('.')
    let ldelta = cpos[1] - marker_pos_current
    call s:set_marker_below(markers['above']['ids'][0], -1)
    call s:set_marker_above(id_cur, markers['above']['ids'][0])
    silent exe p1_other . ',' . p2_other . 'move ' . marker_pos_current
        \. ' | ' . p1 . ',' . p2 . 'move ' . marker_pos_other
    call cursor(marker_pos_other + ldelta, cpos[2])
    call s:set_marker_above(-1, id_cur)

    if g:jukit_highlight_markers
        call jukit#highlight_markers(1)
    endif
    if g:jukit_enable_textcell_bg_hl
        call jukit#place_markdown_cell_signs(1)
    endif
endfun

fun! jukit#cells#move_down() abort
    " affected cell markers: above, below, next but two below
    " assign new cell id to: -
    " effect on output: -

    let markers = jukit#util#get_adjacent_markers()
    if !markers['below']['pos']
        echom '[vim-jukit] No cell below!'
        return
    endif

    let id_cur = markers['below']['ids'][0]
    let p1_other = markers['below']['pos'] + 1
    let p2_other = search('|%%--%%|\(.*<'
        \. join(markers['below']['ids'], '|') . '>\)\@!', 'nW') - 1
    if p2_other == -1
        let p2_other = line('$')
    endif

    if !markers['above']['pos']
        let p1 = 1
    else
        let p1 = markers['above']['pos'] + 1
    endif
    let p2 = markers['below']['pos'] - 1

    let cpos = getpos('.')
    let ldelta = cpos[1] - markers['above']['pos']
    call s:set_marker_above(-1, markers['below']['ids'][1])
    call s:set_marker_below(markers['below']['ids'][1], id_cur)
    silent exe p1 . ',' . p2 . 'move ' . markers['below']['pos'] . ' | ' 
        \. p1_other . ',' . p2_other . 'move ' . markers['above']['pos']
    call cursor(markers['above']['pos'] + p2_other - p1_other + ldelta + 2, cpos[2])
    call s:set_marker_below(id_cur, -1)

    if g:jukit_highlight_markers
        call jukit#highlight_markers(1)
    endif
    if g:jukit_enable_textcell_bg_hl
        call jukit#place_markdown_cell_signs(1)
    endif
endfun
