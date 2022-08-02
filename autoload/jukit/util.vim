let s:script_path = expand("<sfile>:p:h")

fun! s:map_extract_ids(v, l) abort
    let id1 = matchstr(a:v, '|%%--%%|.*<\zs.*\ze|.*>')
    let id2 = matchstr(a:v, '|%%--%%|.*<.*|\zs.*\ze>')
    call add(s:ids1, id1)
    call add(s:ids2, id2)
    call add(s:pos, a:l+1)
endfun

fun! jukit#util#catch_load_json(file, ntries_left, time_between) abort
    "in case file is trying to be loaded while it is being written to by
    "another process. if it still can't be loaded after `ntries_left` then
    "it is assumed that it is corrupted and replaced with empty json
    let f_content = readfile(a:file)
    try
        if has('nvim')
            let json = json_decode(f_content)
        else
            let json = json_decode(join(f_content, ''))
        endif
    catch
        echom "[vim-jukit] could not decode json, number of tries left: " . a:ntries_left
        if a:ntries_left > 0
            exe "sleep " . a:time_between . "m"
            let json = jukit#util#catch_load_json(a:file, a:ntries_left - 1, a:time_between)
            let g:ntries = a:ntries_left
        else
            echom "[vim-jukit] json file not readable, replacing with empty json..."
            let json = {}
            call writefile([json_encode(json)], a:file, 'b')
        endif
    endtry

    return json
endfun

fun! jukit#util#get_all_ids() abort
    let lines = getline(1, line('$'))
    let s:ids1 = []
    let s:ids2 = []
    let s:pos = []
    call map(copy(lines), {l, v -> v =~ '|%%--%%|' ? s:map_extract_ids(v, l) : 0})
    return {1: s:ids1, 2: s:ids2, 'pos': s:pos}
endfun

fun! jukit#util#get_unique_id() abort
    let ids = jukit#util#get_all_ids()
    if len(ids[1])
        let existing_ids = [ids[1][0]] + ids[2]
    else
        let existing_ids = []
    endif
python3 << EOF
import random, string, vim

alphabet = string.ascii_uppercase + string.ascii_lowercase + string.digits
existing_ids = vim.eval('existing_ids')

id_exists = True
while id_exists:
    id = ''.join(random.choices(alphabet, k=10))
    id_exists = id in existing_ids

vim.command(f"let id='{id}'")
EOF
    return id
endfun

fun! jukit#util#get_marker_above() abort
    let marker_pos_above = search('|%%--%%|', 'nbW')
    if marker_pos_above
        let id1 = matchstr(getline(marker_pos_above), '|%%--%%|.*<\zs.*\ze|.*>')
        let id2 = matchstr(getline(marker_pos_above), '|%%--%%|.*<.*|\zs.*\ze>')
        let ids = [id1, id2]
    else
        let id_above = -1
        let ids = []
    endif
    return {'ids': ids, 'pos': marker_pos_above}
endfun

fun! jukit#util#get_marker_below() abort
    let marker_pos_below = search('|%%--%%|', 'nW')
    if marker_pos_below
        let id1 = matchstr(getline(marker_pos_below), '|%%--%%|.*<\zs.*\ze|.*>')
        let id2 = matchstr(getline(marker_pos_below), '|%%--%%|.*<.*|\zs.*\ze>')
        let ids = [id1, id2]
    else
        let ids = []
    endif
    return {'ids': ids, 'pos': marker_pos_below}
endfun

fun! jukit#util#get_adjacent_markers() abort
    let ids_below = jukit#util#get_marker_below()
    let ids_above = jukit#util#get_marker_above()
    return {'below': ids_below, 'above': ids_above}
endfun

fun! jukit#util#get_current_cell_id() abort
    let ids = jukit#util#get_adjacent_markers()
    if ids['above']['pos'] != 0
        let cell_id = ids['above']['ids'][1]
    elseif ids['below']['pos'] != 0
        let cell_id = ids['below']['ids'][0]
    else
        let cell_id = 'NONE'
    endif

    return cell_id
endfun

fun! jukit#util#plugin_path() abort
    " Gets absolute path to the vim-jukit/ folder
    let plugin_path = split(s:script_path, g:_jukit_ps)[:-3]
    if g:_jukit_is_windows
        return join(plugin_path, g:_jukit_ps)
    else
        return g:_jukit_ps . join(plugin_path, g:_jukit_ps)
    endif
endfun

fun! jukit#util#ipython_info_write(keys, texts) abort
    if !g:jukit_ipython
        return
    endif

    let dir = expand('%:p:h') . g:_jukit_ps . '.jukit' . g:_jukit_ps
    let file = dir . '.jukit_info.json'
    if !isdirectory(dir)
        call mkdir(dir)
    endif

    if !empty(glob(file))
        let json = jukit#util#catch_load_json(file, 5, 500)
    else
        let json = {}
    endif

    if type(a:keys) == 3
        if len(a:keys) != len(a:texts)
            echom "[vim-jukit] Keys and texts must have same length!"
            return
        endif

        for i in range(len(a:keys))
            let json[a:keys[i]] = a:texts[i]
        endfor
    else
        let json[a:keys] = a:texts
    endif
    call writefile([json_encode(json)], file, 'b')
endfun

fun! s:get_key(json, key, quiet) abort
    if has_key(a:json, a:key)
        return a:json[a:key]
    elseif !a:quiet
        echom '[vim-jukit] Key "' . a:key . '" not found!'
    endif
    return v:null
endfun

fun! jukit#util#ipython_info_get(keys, ...) abort
    if a:0 > 0
        let quiet = a:1
    else
        let quiet = 0
    endif

    let dir = expand('%:p:h') . g:_jukit_ps . '.jukit' . g:_jukit_ps
    let file = dir . '.jukit_info.json'
    if (empty(glob(file)) || !isdirectory(dir)) && !quiet
        echom '[vim-jukit] File ' . file . ' not found!'
        return v:null
    endif

    if !empty(glob(file))
        let json = jukit#util#catch_load_json(file, 5, 500)
    else
        let json = {}
    endif

    if type(a:keys) == 3
        let vals = []
        call map(a:keys, {k,v -> add(vals, s:get_key(json, v, quiet))})
        return vals
    else
        return s:get_key(json, a:keys, quiet)
    endif
endfun

fun! jukit#util#get_visual_selection() abort
    " Credit for this function: 
    " https://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript/6271254#6271254
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return ''
    endif
    let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction

fun! jukit#util#replace_old_markers() abort
    let id_before = jukit#util#get_unique_id()
    fun s:replace() closure
        let new_id = jukit#util#get_unique_id()
        let ids_str =  ' <' . id_before . '|' . new_id . '>'
        let repl = substitute(getline('.'), '|%%--%%|\zs.*\ze', ids_str, 'g')
        call setline(line('.'), repl)
        let id_before = new_id
    endfun

    let id = 1
    let save_view = winsaveview()
    g/|%%--%%|/call s:replace()
    call winrestview(save_view)
endfun

fun! jukit#util#get_terminal() abort
    let kitty_detected = system('perl -lpe "s/\0/ /g" /proc/$(xdotool '
        \. 'getwindowpid $(xdotool getactivewindow))/cmdline') =~? 'kitty'
        \ || system('echo $TERM') =~? 'kitty'
    let tmux_detected = system('if [ -n "$TMUX" ]; then echo 1; else echo 0; fi')
    if kitty_detected
        return 'kitty'
    elseif tmux_detected
        return 'tmux'
    elseif has('nvim')
        return 'nvimterm'
    else
        return 'vimterm'
    endif
endfun

fun! jukit#util#get_lang_info() abort
python3 << EOF
import vim, os, sys, json
sys.path.append(vim.eval('jukit#util#plugin_path() . g:_jukit_ps . "helpers"'))
from ipynb_convert import languages

vim.command(f"let json='{json.dumps(languages)}'")
EOF
    let json = json_decode(json)
    if has_key(json, tolower(&ft))
        let ft_json = json[tolower(&ft)]
        let md_start = ft_json['multiline_start'] . g:_jukit_md_mark
        let md_end = g:_jukit_md_mark . ft_json['multiline_end']
        let cchar = ft_json['cchar']
        let ext = ft_json['ext']
        let success = 1
    else
        let md_start = "\"\"\"" . g:_jukit_md_mark
        let md_end = g:_jukit_md_mark . "\"\"\""
        let cchar = "#"
        let ext = 'py'
        let success = 0
    endif
    return [md_start, md_end, cchar, ext, success]
endfun

fun! jukit#util#md_buffer_vars() abort
    if exists('b:jukit_md_start')
        return
    endif
    let md_info = jukit#util#get_lang_info()
    let b:jukit_md_start = md_info[0]
    let b:jukit_md_end =  md_info[1]
    let b:jukit_cchar =  md_info[2]
    let b:jukit_md_start_escaped = escape(b:jukit_md_start, '/*')
    let b:jukit_md_end_escaped =  escape(b:jukit_md_end, '/*')
endfun

fun! jukit#util#is_valid_version(vcur, vreq) abort
    " expects lists of length 3 according to semantic versioning convention

    if len(a:vcur)!=3 || len(a:vreq)!=3
        echom '[vim-jukit] invalid version number encountered:'
        echom a:vcur
        echom a:vreq
        return 1 " by default give benefit of the doubt if a version number not in the expected format
    endif

    let valid1 = a:vcur[0] >= a:vreq[0]
    let valid2 = a:vcur[0] > a:vreq[0] || valid1 && a:vcur[1] >= a:vreq[1]
    let valid3 = a:vcur[0] > a:vreq[0] || a:vcur[1] > a:vreq[1] || valid1 && valid2 && a:vcur[2] >= a:vreq[2]

    return (valid1 && valid2 && valid3)
endfun
