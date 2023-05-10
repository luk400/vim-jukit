if g:jukit_kill_ueberzug_on_focus_lost
    au BufLeave,WinLeave,TabLeave,FocusLost <buffer> :call s:kill_ueberzug()
else
    au BufLeave,WinLeave,TabLeave <buffer> :call s:kill_ueberzug()
endif

fun! s:get_ueberzug_options()
    return "--border_color=" . g:jukit_ueberzug_border_color
        \. " --theme=" . g:jukit_ueberzug_theme
        \. ' --python_cmd="' . g:jukit_ueberzug_python_cmd . '"'
        \. ' --jupyter_cmd="' . g:jukit_ueberzug_jupyter_cmd . '"'
        \. ' --cutycapt_cmd="' . g:jukit_ueberzug_cutycapt_cmd . '"'
        \. ' --imagemagick_cmd="' . g:jukit_ueberzug_imagemagick_cmd . '"'
endfun

fun! jukit#ueberzug#set_default_pos() abort
    call s:show_template_img('distort')
    if g:_jukit_display == 0
        call s:show_template_img('distort')
    endif

    let display_param = s:get_default_display_param()['display_param']
    let xpos = display_param['xpos']
    let ypos = display_param['ypos']
    let width = display_param['width_prop']
    let height = display_param['height_prop']

    let choices = [[-0.01,0.0], [0.01,0.0], [0.0,0.01], [0.0,-0.01]]
    let choice_idx = -1
    while choice_idx != 10
        let choice_idx = confirm("Configure position (hjkl), width (<>), and maximum height (+-):",
            \ "&h\n&l\n&j\n&k\n&<\n&>\n&+\n&-\n&Reset\n&Accept", 10)

        if choice_idx <= 4
            let xpos += choices[choice_idx-1][0]
            let ypos += choices[choice_idx-1][1]
        elseif (choice_idx > 4) && (choice_idx <= 8)
            let width += choices[choice_idx-5][0]
            let height += choices[choice_idx-5][1]
            let width = width < 0.05 ? 0.05 : width
            let height = height < 0.05 ? 0.05 : height
        elseif choice_idx == 9
            let xpos = 0.25
            let ypos = 0.25
            let width = 0.4
            let height = 0.6
        endif

        let display_param['xpos'] = xpos
        let display_param['ypos'] = ypos
        let display_param['width_prop'] = width
        let display_param['height_prop'] = height

        if !jukit#splits#split_exists('output')
            let suffix = '_noout'
            let g:jukit_ueberzug_pos_noout = [xpos, ypos, width, height]
        else
            let suffix = ''
            let g:jukit_ueberzug_pos = [xpos, ypos, width, height]
        endif

        let params = {'display_param': display_param}
        call jukit#util#ipython_info_write(params)
        redraw
    endwhile

    call s:kill_ueberzug()

    let info = 'WITH output split present'
    if !jukit#splits#split_exists('output')
        let info = 'WITHOUT output split present'
    endif

    echom "[vim-jukit] Default settings (" . info . ") set to: [x, y, width, height] = [" 
        \ . string(xpos) . ", " . string(ypos) . ", " . string(width) . ", " 
        \ . string(height) . "]"
    echom "[vim-jukit] To make these the default each time, specifiy "
        \. "`let g:jukit_ueberzug_pos" . suffix . " = [" . string(xpos) . ", "
        \. string(ypos) . ", " . string(width) . ", " . string(height) . "]` "
        \. "in your vim config!"
endfun

fun! jukit#ueberzug#show_last_cell_output(force) abort
    if !exists('g:jukit_outhist_last_cell')
        let g:jukit_outhist_last_cell = -1
    endif

    let cell_id = jukit#util#get_current_cell_id()
    if cell_id == g:jukit_outhist_last_cell && !a:force
        return
    endif

    let save_view = winsaveview()
    let g:jukit_outhist_last_cell = cell_id

    if exists('g:_jukit_display') && g:_jukit_display
        echom '[vim-jukit] close überzug'
        call s:kill_ueberzug()
		call s:kill_mdnb_outhist_timer()
        if a:force
            return
        endif
        call jukit#ueberzug#show_last_cell_output(a:force)
    else
        echom '[vim-jukit] show saved outputs...'
    endif
    
    let g:_jukit_display = 1
    let params = s:get_default_display_param()

    call jukit#util#ipython_info_write(params)
    let cell_id = jukit#util#get_current_cell_id()
    let dir = escape(expand('%:p:h'), ' \')
    let fname = escape(expand('%:t:r'), ' \')
    let output_json = dir . '/.jukit/' . fname . '_outhist.json'

    let truncated_files = jukit#util#ipython_info_get('truncated_files', 1)
    if type(truncated_files) != 7 && has_key(truncated_files, cell_id)
        let full_html = truncated_files[cell_id]
        if !empty(glob(full_html))
            let answer = confirm('[vim-jukit] Saved outputs '
                \ . 'were too large for a single image. Do you want to open an html '
                \ . 'with all outputs instead of the truncated image?', "&Yes\n&No", 1)
            if answer == 1
                call system(g:jukit_html_viewer . ' ' . full_html)
                call winrestview(save_view)
                return
            endif
        endif
    endif

    call jukit#util#md_buffer_vars()
    let md_cur = jukit#util#is_md_cell(cell_id)
    if md_cur
        let ipynb_file = dir . '/.jukit/' . fname . '_outhist.ipynb'
        call s:convert_md_to_ipynb(cell_id, ipynb_file)
		call s:create_mdnb_outhist_timer(cell_id, ipynb_file)
        let cmd = 'python3 ' . jukit#util#plugin_path() . '/helpers/ueberzug_output/show_output.py ' 
            \ . s:get_ueberzug_options() . ' markdown --use_cached=' . g:jukit_ueberzug_use_cached_md
            \ . ' ' . cell_id . ' "' . ipynb_file . '"'
    else
        let cmd = 'python3 ' . jukit#util#plugin_path() . '/helpers/ueberzug_output/show_output.py ' 
            \ . s:get_ueberzug_options() . ' output --use_cached=' . g:jukit_ueberzug_use_cached
            \ . ' ' . cell_id . ' "' . output_json . '"'
    endif

    if g:jukit_debug
        echom '[vim-jukit] ueberzug command: ' . cmd
    endif

    if has('nvim')
        noautocmd enew
        call termopen(cmd, {'on_exit': 'OnExit', 'bufnr': bufnr('%')}) | set nobl
        edit #
    else
        noautocmd exec "term ++hidden " . cmd
    endif

    call winrestview(save_view)
endfun

fun! OnExit(job_id, code, event) dict
    if a:code == 0
        exec 'bdelete ' . self.bufnr
    endif
endfun

fun! s:create_mdnb_outhist_timer(cell_id, ipynb_file) abort
    let b:_jukit_mdnb_timer_id = timer_start(str2nr(string(1000 * g:_jukit_mdnb_timer)),
        \ s:create_mdcell_timer(a:cell_id, a:ipynb_file), {'repeat': -1})
    
    if g:jukit_kill_ueberzug_on_focus_lost
        autocmd BufLeave,WinLeave,TabLeave,FocusLost <buffer> :call s:kill_mdnb_outhist_timer()
    else
        autocmd BufLeave,WinLeave,TabLeave <buffer> :call s:kill_mdnb_outhist_timer()
    endif
endfun

fun! s:kill_mdnb_outhist_timer() abort
    if !exists('b:_jukit_mdnb_timer_id')
        return
    endif

    call timer_stop(b:_jukit_mdnb_timer_id)
endfun

fun! s:create_mdcell_timer(cell_id, ipynb_file) abort
    let cell_id = a:cell_id
    let ipynb_file = a:ipynb_file
    exe ""
        \. "fun! s:create_mdcell(timer)\n"
        \. "    let save_view = winsaveview()\n"
        \. "    let lnum1 = search('|" . cell_id . ">')\n"
        \. "    let lnum2 = search('<" . cell_id . "|')\n"
        \. "    if lnum1\n"
        \. "        call cursor(lnum1+1, 1)\n"
        \. "    elseif lnum2\n"
        \. "        call cursor(lnum2-1, 1)\n"
        \. "    endif\n"
        \. "    call s:convert_md_to_ipynb('" . cell_id . "','" . ipynb_file . "')\n"
        \. "    call winrestview(save_view)\n"
        \. "endfun\n"

    return function('s:create_mdcell')
endfun

fun! s:show_template_img(scaler) abort
    let save_view = winsaveview()

    if exists('g:_jukit_display') && g:_jukit_display
        call s:kill_ueberzug()
        return
    endif
    
    let g:_jukit_display = 1
    let params = s:get_default_display_param()
    call jukit#util#ipython_info_write(params)
    let cmd = 'python3 ' . jukit#util#plugin_path() . '/helpers/ueberzug_output/show_output.py ' 
        \. s:get_ueberzug_options() . ' config "' . jukit#util#plugin_path()
        \. '/helpers/ueberzug_output/templates/pos_template.png" "'
        \. escape(expand('%:p:h'), ' \') . '/.jukit" --scaler=' . a:scaler

    if has('nvim')
        noautocmd exec "term " . cmd
        edit #
    else
        noautocmd exec "term ++hidden " . cmd
    endif

    call winrestview(save_view)
endfun

fun! s:convert_md_to_ipynb(cell_id, ipynb_file)
    call jukit#util#md_buffer_vars()

    let pos1 = search('|%%--%%|', 'nbW') + 2
    let pos2 = search('|%%--%%|', 'nW')

    if pos2 != 0
        let pos2 -= 2
    else
        let pos2 = line('$')-1
    endif

    let text = join(getline(pos1, pos2), "\n")
    let nb = s:get_md_nb(text)

    call writefile([json_encode(nb)], a:ipynb_file, 'b')
endfun

fun! s:get_md_nb(text)
    let cell = {
        \ "cell_type": "markdown",
        \ "source": a:text,
        \ "metadata": {},
    \ }

    let nb = {
        \ "cells": [cell],
        \ "metadata": {},
        \ "nbformat": 4,
        \ "nbformat_minor": 4,
    \ }

    return nb
endfun

fun! s:kill_ueberzug()
    let display_param = s:get_default_display_param()['display_param']
    let display_param['display'] = 0
    call jukit#util#ipython_info_write({'display_param': display_param})
    let g:_jukit_display = 0
    sleep 100m
endfun

fun! s:get_num_cols_in_line(key, line)
    call cursor(a:line, 1)
    " TODO: &columns also contains out-of-bounds columns. We need only the 
    " columns from the text buffer
    let g:_jukit_sum += virtcol('$') / &columns
endfun

fun! s:get_default_display_param()
    let cell_end = jukit#util#get_marker_below()['pos']
    if cell_end == 0
        let cell_end = line('$')
    endif

    if jukit#splits#split_exists('output')
        let params = {'display_param': {
            \ 'columns': &columns,
            \ 'lines': &lines,
            \ 'display': g:_jukit_display,
            \ 'scroll_pos': 0,
            \ 'xpos': g:jukit_ueberzug_pos[0],
            \ 'ypos': g:jukit_ueberzug_pos[1],
            \ 'width_prop': g:jukit_ueberzug_pos[2],
            \ 'height_prop': g:jukit_ueberzug_pos[3],
            \ 'timestamp': reltimestr(reltime()),
            \ 'term_hw_ratio': g:jukit_ueberzug_term_hw_ratio,
            \ 'html_viewer': g:jukit_html_viewer}}
    else
        let params = {'display_param': {
            \ 'columns': &columns,
            \ 'lines': &lines,
            \ 'display': g:_jukit_display,
            \ 'scroll_pos': 0,
            \ 'xpos': g:jukit_ueberzug_pos_noout[0],
            \ 'ypos': g:jukit_ueberzug_pos_noout[1],
            \ 'width_prop': g:jukit_ueberzug_pos_noout[2],
            \ 'height_prop': g:jukit_ueberzug_pos_noout[3],
            \ 'timestamp': reltimestr(reltime()),
            \ 'term_hw_ratio': g:jukit_ueberzug_term_hw_ratio,
            \ 'html_viewer': g:jukit_html_viewer}}
    endif

    return params
endfun

fun! jukit#ueberzug#scroll(down) abort
    let display_param = jukit#util#ipython_info_get(['display_param'], 1)[0]

    let display_param['timestamp'] = reltimestr(reltime())
    if a:down
        let display_param['scroll_pos'] = 1
    else
        let display_param['scroll_pos'] = -1
    endif

    let params = {'display_param': display_param}

    call jukit#util#ipython_info_write(params)
endfun

fun! jukit#ueberzug#horizontal_scroll(down) abort
    echom "[vim-jukit] jukit#ueberzug#horizontal_scroll() not yet implemented"
endfun

fun! jukit#ueberzug#zoom(factor) abort
    echom "[vim-jukit] jukit#ueberzug#scroll() not yet implemented"
endfun
