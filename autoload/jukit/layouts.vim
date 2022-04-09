fun! s:check_dict_validity(layout) abort
    let d = a:layout
    if sort(keys(d)) != ['p1', 'split', 'val']
        echom '[vim-jukit] g:jukit_layout: invalid keys in dict'
        return 0
    endif

    let val_valid = type(d['val']) == 3 && len(d['val']) == 2 
        \ && sort([type(d['val'][0]), type(d['val'][1])]) == [1, 4]
    if !val_valid
        echom '[vim-jukit] g:jukit_layout: `val` must be a list containing a '
            \. 'string and a dictionary'
        return 0
    endif

    let idx_str = index([type(d['val'][0]), type(d['val'][1])], 1)
    let idx_d = 1 - idx_str

    if sort(keys(d['val'][idx_d])) != ['p1', 'split', 'val']
        echom '[vim-jukit] g:jukit_layout: invalid keys in inner dict'
        return 0
    endif

    let val_valid = type(d['val'][idx_d]['val']) == 3 && len(d['val'][idx_d]['val']) == 2 
        \ && [type(d['val'][idx_d]['val'][0]), type(d['val'][idx_d]['val'][1])] == [1, 1]
    if !val_valid
        echom '[vim-jukit] g:jukit_layout: `val` in inner dict must be a list '
            \. 'containing two strings'
        return 0
    endif

    let split_vals = [d['split'], d['val'][idx_d]['split']]
    let spl_psbl = ['horizontal', 'vertical']
    let splits_valid = index(spl_psbl, split_vals[0]) >= 0 && index(spl_psbl, split_vals[1]) >= 0

    let p1_vals = [d['p1'], d['val'][idx_d]['p1']]
    let p1_valid = p1_vals[0] > 0 && p1_vals[0] < 1 && p1_vals[1] > 0 && p1_vals[1] < 1

    let str_vals = [d['val'][idx_str], d['val'][idx_d]['val'][0],
        \ d['val'][idx_d]['val'][1]]
    let str_valid = sort(str_vals) == ['file_content', "output", "output_history"]


    if !splits_valid
        echom '[vim-jukit] g:jukit_layout: `split` values must be one of: '
            \. '["horizontal", "vertical"]'
        return 0
    elseif !p1_valid
        echom '[vim-jukit] g:jukit_layout: `p1` must be a float value with 0 < p1 < 1'
        return 0
    elseif !str_valid
        echom '[vim-jukit] g:jukit_layout: `val` strings must be one of: '
            \. '["file_content", "output", "output_history"]'
        return 0
    endif

    return 1
endfun

fun! jukit#layouts#set_layout(...) abort
    if type(g:jukit_layout) != 4
        return
    endif

    if a:0 > 0
        let layout = a:1
        let dict_valid = s:check_dict_validity(g:jukit_layout)
    else
        let layout = g:jukit_layout
        let dict_valid = s:dict_valid
    endif

    if !dict_valid
        return
    endif

    let layout = layout
    exe 'call jukit#' . g:jukit_terminal . '#layouts#set_layout(layout)'
endfun

if type(g:jukit_layout) == 4
    let s:dict_valid = s:check_dict_validity(g:jukit_layout)
endif
