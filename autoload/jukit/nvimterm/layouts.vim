fun! s:get_buf_by_name(name, output_exists) abort
    if a:name == 'file_content'
        return bufnr('%')
    elseif a:name == 'output' && a:output_exists
        return g:jukit_output_buf
    else
        return -1
    endif
endfun

" Set up a two-pane nvimterm layout: file_content + output. Layout dict
" shape: {'split': 'horizontal'|'vertical', 'p1': 0.0..1.0, 'val':
" [pane1, pane2]} where each entry is the literal string 'file_content'
" or 'output'.
fun! jukit#nvimterm#layouts#set_layout(layout) abort
    let output_exists = jukit#nvimterm#splits#exists('output')
    if !output_exists
        echom "[vim-jukit] No output buffer present for layout"
        return
    endif

    if type(a:layout['val'][0]) != 1 || type(a:layout['val'][1]) != 1
        echom "[vim-jukit] Invalid layout dict: expected two named panes"
        return
    endif

    let save_view = winsaveview()

    let file_buf = s:get_buf_by_name('file_content', output_exists)
    let output_buf = s:get_buf_by_name('output', output_exists)

    " Pane 0 is on the left/top, pane 1 is on the right/bottom.
    " p1 is the fractional size of pane 0.
    if a:layout['val'][0] == 'file_content'
        let left_buf = file_buf
        let right_buf = output_buf
    else
        let left_buf = output_buf
        let right_buf = file_buf
    endif

    exe bufwinnr(right_buf) . 'wincmd w'
    if a:layout['split'] == 'horizontal'
        wincmd L
        let win = bufwinnr(left_buf)
        exe 'vert ' . win . 'resize ' . float2nr(a:layout['p1'] * &columns)
    else
        wincmd J
        let win = bufwinnr(left_buf)
        exe win . 'resize ' . float2nr(a:layout['p1'] * &lines)
    endif

    exe bufwinnr(g:_jukit_main_buf) . 'wincmd w'
    call winrestview(save_view)
endfun
