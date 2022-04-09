fun! s:get_buf_by_name(name, output_exists, outhist_exists) abort
    if a:name == 'file_content'
        return bufnr('%')
    elseif a:name == 'output' && a:output_exists
        return g:jukit_output_buf
    elseif a:name == 'output_history' && a:outhist_exists
        return g:jukit_outhist_buf
    else
        return -1
    endif
endfun

fun! s:parse_layout(layout, op, oh) abort
    let inner_pair = {}
    let outer_buf = {'split': a:layout['split'], 'bias': a:layout['p1']}

    if type(a:layout["val"][0]) == 4
        let d = a:layout["val"][0]
        let outer_buf['buf'] = s:get_buf_by_name(a:layout["val"][1], a:op, a:oh)
        let outer_buf['top_or_left'] = 0
        let inner_pair['buf'] = [s:get_buf_by_name(d["val"][0], a:op, a:oh), 
            \ s:get_buf_by_name(d["val"][1], a:op, a:oh)]
    elseif type(a:layout["val"][1]) == 4
        let d = a:layout["val"][1]
        let outer_buf['buf'] = s:get_buf_by_name(a:layout["val"][0], a:op, a:oh)
        let outer_buf['top_or_left'] = 1
        let inner_pair['buf'] = [s:get_buf_by_name(d["val"][0], a:op, a:oh),
            \ s:get_buf_by_name(d["val"][1], a:op, a:oh)]
    else
        echom "[vim-jukit] Invalid layout dict!"
        return v:null
    endif

    let inner_pair['split'] = d["split"]
    let inner_pair['bias'] = d["p1"]

    return [inner_pair, outer_buf]
endfun

fun! jukit#nvimterm#layouts#set_layout(layout) abort
    let output_exists = jukit#nvimterm#splits#exists('output')
    let outhist_exists = jukit#nvimterm#splits#exists('outhist')
    if !output_exists && !outhist_exists
        echom "[vim-jukit] No windows for layout present"
        return
    elseif !output_exists || !outhist_exists
        let only_one = 1
    else
        let only_one = 0
    endif

    let save_view = winsaveview()
    let response = s:parse_layout(a:layout, output_exists, outhist_exists)

    if type(response) == 7
        return
    endif

    let inner_pair = response[0]
    let outer_buf = response[1]

    let bufs_filtered = filter(reverse(copy(inner_pair['buf'])), {k,v -> v != -1})
    for b in bufs_filtered
        exe bufwinnr(b) . 'wincmd w'
        if inner_pair['split'] == "horizontal"
            wincmd H
        else
            wincmd K
        endif
    endfor

    if outer_buf['buf'] != -1
        exe bufwinnr(outer_buf['buf']) . 'wincmd w'
        if outer_buf['split'] == "horizontal"
            if outer_buf['top_or_left']
                wincmd H
            else
                wincmd L
            endif
            let win = bufwinnr(outer_buf['buf'])
            exe 'vert ' . win . 'resize ' . float2nr(outer_buf['bias'] * &columns)
        else
            if outer_buf['top_or_left']
                wincmd K
            else
                wincmd J
            endif
            let win = bufwinnr(outer_buf['buf'])
            exe win . 'resize ' . float2nr(outer_buf['bias'] * &lines)
        endif
    endif

    if inner_pair['buf'][0] != -1 && inner_pair['buf'][1] != -1
        exe bufwinnr(inner_pair['buf'][0]) . 'wincmd w'
        let win = bufwinnr(inner_pair['buf'][0])
        let scale = 1 - outer_buf['bias'] * (inner_pair['split'] == outer_buf['split'])
        if inner_pair['split'] == "horizontal"
            exe 'vert ' . win . 'resize ' . float2nr(scale * inner_pair['bias'] * &columns)
        else
            exe win . 'resize ' . float2nr(scale * inner_pair['bias'] * &lines)
        endif
    endif

    exe bufwinnr(g:_jukit_main_buf) . 'wincmd w'
    call winrestview(save_view)
endfun
