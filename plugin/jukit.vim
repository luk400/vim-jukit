""""""""""""""""""
" global variables
""""""""""""""""""

let s:default_layout = {
    \'split': 'horizontal',
    \'p1': 0.6, 
    \'val': [
        \'file_content',
        \{
            \'split': 'vertical',
            \'p1': 0.6,
            \'val': ['output', 'output_history']
        \}
    \]
\}

" jukit 
let g:jukit_mappings_ext_enabled = get(g:, 'jukit_mappings_ext_enabled', '*')
let g:jukit_shell_cmd = get(g:, 'jukit_shell_cmd', 'ipython3')
let g:jukit_layout = get(g:, 'jukit_layout', s:default_layout)
let g:jukit_terminal = get(g:, 'jukit_terminal', '')
let g:jukit_use_tcomment = get(g:, 'jukit_use_tcomment', 0)
let g:jukit_comment_mark = get(g:, 'jukit_comment_mark', '#')
let g:jukit_auto_output_hist = get(g:, 'jukit_auto_output_hist', 0)
let g:jukit_mappings = get(g:, 'jukit_mappings', 1)
let g:_jukit_python_os_cmd = get(g:, 'jukit_python_os_cmd', 'python3')

let g:jukit_html_viewer = get(g:, 'jukit_html_viewer', 'xdg-open')
let g:jukit_ipython = get(g:, 'jukit_ipython', split(g:jukit_shell_cmd, '/')[-1] =~ 'ipython')
let g:jukit_debug = get(g:, 'jukit_debug', 0)
if has('win32')
    let g:_jukit_is_windows = 1
    let g:_jukit_python = split(g:jukit_shell_cmd, '\')[-1] =~ 'python'
else
    let g:_jukit_is_windows = 0
    let g:_jukit_python = split(g:jukit_shell_cmd, '/')[-1] =~ 'python'
endif
let g:_jukit_md_mark = '°°°'
let g:jukit_version = 'v1.3.3'
let g:jukit_convert_overwrite_default = get(g:, 'jukit_convert_overwrite_default', -1)
let g:jukit_convert_open_default = get(g:, 'jukit_convert_open_default', -1)

" (i)python
let g:jukit_in_style = get(g:, 'jukit_in_style', 2)
let g:jukit_max_size = get(g:, 'jukit_max_size', 20)
let g:jukit_ipy_opts = get(g:, 'jukit_ipy_opts', '')
let g:jukit_show_prompt = get(g:, 'jukit_show_prompt', 0)
let g:jukit_save_output = get(g:, 'jukit_save_output', g:jukit_ipython)
let g:jukit_clean_outhist_freq = get(g:, 'jukit_clean_outhist_freq', 60 * 10)

" kitty
let g:jukit_output_bg_color = get(g:, 'jukit_output_bg_color', '')
let g:jukit_output_fg_color = get(g:, 'jukit_output_fg_color', '')
let g:jukit_outhist_bg_color = get(g:, 'jukit_outhist_bg_color', '#090b1a')
let g:jukit_outhist_fg_color = get(g:, 'jukit_outhist_fg_color', 'gray')
let g:jukit_output_new_os_window = get(g:, 'jukit_output_new_os_window', 0)
let g:jukit_outhist_new_os_window = get(g:, 'jukit_outhist_new_os_window', 0)

" matplotlib
let g:jukit_mpl_style = get(g:, 'jukit_mpl_style', '') "this value is changed for kitty after version checking below
let g:jukit_savefig_dpi = get(g:, 'jukit_savefig_dpi', 150)
let g:jukit_custom_backend = get(g:, 'jukit_custom_backend', -1)
let g:jukit_mpl_block = get(g:, 'jukit_mpl_block', 1)

" cell highlighting/syntax
if g:_jukit_is_windows
    let g:jukit_text_syntax_file = get(g:, 'jukit_text_syntax_file', $VIMRUNTIME . '\syntax\' . 'markdown.vim')
else
    let g:jukit_text_syntax_file = get(g:, 'jukit_text_syntax_file', $VIMRUNTIME . '/syntax/' . 'markdown.vim')
endif
let g:jukit_hl_ext_enabled = get(g:, 'jukit_hl_ext_enabled', '*')
let g:jukit_highlight_markers = get(g:, 'jukit_highlight_markers', 1)
let g:jukit_enable_textcell_bg_hl = get(g:, 'jukit_enable_textcell_bg_hl', 1)
let g:jukit_enable_textcell_syntax = get(g:, 'jukit_enable_textcell_syntax', 1)

" ueberzug
let g:jukit_hist_use_ueberzug = get(g:, 'jukit_hist_use_ueberzug', 0)
let g:jukit_ueberzug_use_cached = get(g:, 'jukit_ueberzug_use_cached', 1)
let g:jukit_ueberzug_use_cached_md = get(g:, 'jukit_ueberzug_use_cached_md', 1)
let g:jukit_ueberzug_pos = get(g:, 'jukit_ueberzug_pos', [0.25, 0.25, 0.4, 0.6])
let g:jukit_ueberzug_pos_noout = get(g:, 'jukit_ueberzug_pos_noout', [0.25, 0.25, 0.4, 0.6])
let g:jukit_ueberzug_term_hw_ratio = get(g:, 'jukit_ueberzug_term_hw_ratio', -1)
let g:_jukit_mdnb_timer = get(g:, '_jukit_mdnb_timer', 0.5)

let g:jukit_kill_ueberzug_on_focus_lost = get(g:, 'jukit_kill_ueberzug_on_focus_lost', 1)
let g:jukit_ueberzug_border_color = get(g:, 'jukit_ueberzug_border_color', 'blue')
let g:jukit_ueberzug_theme = get(g:, 'jukit_ueberzug_theme', 'dark')
let g:jukit_ueberzug_python_cmd = get(g:, 'jukit_ueberzug_python_cmd', 'python3')
let g:jukit_ueberzug_jupyter_cmd = get(g:, 'jukit_ueberzug_jupyter_cmd', 'jupyter')
let g:jukit_ueberzug_cutycapt_cmd = get(g:, 'jukit_ueberzug_cutycapt_cmd', 'cutycapt')
let g:jukit_ueberzug_imagemagick_cmd = get(g:, 'jukit_ueberzug_imagemagick_cmd', 'convert')

" requirements
let g:jukit_required_kitty_version = [0,22,0]
let g:jukit_required_vim_version = [8,1,0]
let g:jukit_required_neovim_version = [0,4,0]
let g:jukit_required_ipython_version = [7,3,0]


""""""""""""""""""""""""""""""""""""""""""
" check requirements and variable validity
""""""""""""""""""""""""""""""""""""""""""

if !has('python3')
    echom "[vim-jukit] python3 support missing! (`:echo has('python3')` returned 0)"
endif

if has('nvim')
    let s:nvim_version = matchstr(execute('version'), '.\{-}NVIM v\zs[0-9\.]\{1,}')
    let s:v_split = split(s:nvim_version, '\.')
    while len(s:v_split) < 3
        call add(s:v_split, 0)
    endwhile

    if !jukit#util#is_valid_version(s:v_split, g:jukit_required_neovim_version)
        echom '[vim-jukit] Insufficient neovim version! (Required version >= '
            \ . join(g:jukit_required_neovim_version, '.') . ' - Current version: '
            \ . s:nvim_version . ') -> Please update neovim to use this plugin!'
    endif
else
    let s:vim_version = matchstr(execute('version'), '.\{-}VIM - Vi IMproved \zs[0-9\.]\{1,}')
    let s:v_split = split(s:vim_version, '\.')
    while len(s:v_split) < 3
        call add(s:v_split, 0)
    endwhile

    let s:valid_vim = jukit#util#is_valid_version(
        \ s:v_split, g:jukit_required_vim_version) && exists("*sign_unplace")
    if !s:valid_vim
        echom '[vim-jukit] Insufficient vim version! (Required version >= '
            \ . join(g:jukit_required_vim_version, '.') . ' - Current version: '
            \ . s:vim_version . ') -> Please update vim to use this plugin!'
    endif
endif

let supported_term = ['vimterm', 'nvimterm', 'kitty', 'tmux']
if g:jukit_terminal is# ''
    let g:jukit_terminal = jukit#util#get_terminal()
elseif index(supported_term, g:jukit_terminal) < 0
    let s:invalid_term = g:jukit_terminal
    if has('nvim')
        let g:jukit_terminal = 'nvimterm'
    else
        let g:jukit_terminal = 'vimterm'
    endif
    echom '[vim-jukit] Invalid value for g:jukit_terminal: ' . s:invalid_term
        \ . ' -> Using `' . g:jukit_terminal . '` instead!'
endif

if !exists('g:jukit_inline_plotting')
    if index(['vimterm', 'nvimterm'], g:jukit_terminal) >= 0
        let g:jukit_inline_plotting = 0
    else
        let g:jukit_inline_plotting = 1
    endif
endif

if g:_jukit_is_windows
    let g:_jukit_ps = '\\'
    let g:_jukit_send_delay = "100m"
    let g:_jukit_is_windows = 1
else
    let g:_jukit_ps = '/'
    let g:_jukit_is_windows = 0
endif

""""""""""
" autocmds 
""""""""""

if type(g:jukit_hl_ext_enabled) == 1
    let g:jukit_hl_ext_enabled = [g:jukit_hl_ext_enabled]
endif
if index(g:jukit_hl_ext_enabled, '*') >= 0
    let s:jukit_ext_aupat = '*'
else
    let s:jukit_ext_aupat = '*.' . join(g:jukit_hl_ext_enabled, ',*.')
endif
call jukit#highlighting_setup(s:jukit_ext_aupat)

if g:jukit_save_output
    exe 'autocmd TextChanged,InsertLeave *.py call jukit#check_ids()'
endif


""""""""""
" commands
""""""""""

command! -nargs=1 JukitOut :call jukit#splits#output(<q-args>)
command! -nargs=1 JukitOutHist :call jukit#splits#output_and_history(<q-args>)


""""""""""
" Mappings
""""""""""

fun! s:set_mappings() abort
    " splits
    if !hasmapto('jukit#splits#output', 'n')
        nnoremap <buffer> <leader>os <cmd>call jukit#splits#output()<cr>
    endif
    if !hasmapto('jukit#splits#term', 'n')
        nnoremap <buffer> <leader>ts <cmd>call jukit#splits#term()<cr>
    endif
    if !hasmapto('jukit#splits#history', 'n')
        nnoremap <buffer> <leader>hs <cmd>call jukit#splits#history()<cr>
    endif
    if !hasmapto('jukit#splits#output_and_history', 'n')
        nnoremap <buffer> <leader>ohs <cmd>call jukit#splits#output_and_history()<cr>
    endif
    if !hasmapto('jukit#splits#close_history', 'n')
        nnoremap <buffer> <leader>hd <cmd>call jukit#splits#close_history()<cr>
    endif
    if !hasmapto('jukit#splits#close_output_split', 'n')
        nnoremap <buffer> <leader>od <cmd>call jukit#splits#close_output_split()<cr>
    endif
    if !hasmapto('jukit#splits#close_output_and_history', 'n')
        nnoremap <buffer> <leader>ohd <cmd>call jukit#splits#close_output_and_history(1)<cr>
    endif
    if !hasmapto('jukit#splits#out_hist_scroll(1)', 'n')
        nnoremap <buffer> <leader>j <cmd>call jukit#splits#out_hist_scroll(1)<cr>
    endif
    if !hasmapto('jukit#splits#out_hist_scroll(0)', 'n')
        nnoremap <buffer> <leader>k <cmd>call jukit#splits#out_hist_scroll(0)<cr>
    endif
    if !hasmapto('jukit#splits#show_last_cell_output', 'n')
        nnoremap <buffer> <leader>so <cmd>call jukit#splits#show_last_cell_output(1)<cr>
    endif
    if !hasmapto('jukit#ueberzug#set_default_pos', 'n')
        nnoremap <buffer> <leader>pos <cmd>call jukit#ueberzug#set_default_pos()<cr>
    endif
    if !hasmapto('jukit#splits#toggle_auto_hist', 'n')
        nnoremap <buffer> <leader>ah <cmd>call jukit#splits#toggle_auto_hist()<cr>
    endif
    if !hasmapto('jukit#layouts#set_layout', 'n')
        nnoremap <buffer> <leader>sl <cmd>call jukit#layouts#set_layout()<cr>
    endif

    " sending code
    if !hasmapto('jukit#send#line', 'n')
        nnoremap <buffer> <cr> <cmd>call jukit#send#line()<cr>
    endif
    if !hasmapto('jukit#send#selection', 'v')
        vnoremap <buffer> <cr> <esc><cmd>call jukit#send#selection()<cr>
    endif
    if !hasmapto('jukit#send#section', 'n')
        nnoremap <buffer> <leader><space> <cmd>call jukit#send#section(0)<cr>
    endif
    if !hasmapto('jukit#send#until_current_section', 'n')
        nnoremap <buffer> <leader>cc <cmd>call jukit#send#until_current_section()<cr>
    endif
    if !hasmapto('jukit#send#all', 'n')
        nnoremap <buffer> <leader>all <cmd>call jukit#send#all()<cr>
    endif

    " cells
    if !hasmapto('jukit#cells#delete', 'n')
        nnoremap <buffer> <leader>cd <cmd>call jukit#cells#delete()<cr>
    endif
    if !hasmapto('jukit#cells#split', 'n')
        nnoremap <buffer> <leader>cs <cmd>call jukit#cells#split()<cr>
    endif
    if !hasmapto('jukit#cells#create_below(0)', 'n')
        nnoremap <buffer> <leader>co <cmd>call jukit#cells#create_below(0)<cr>
    endif
    if !hasmapto('jukit#cells#create_above(0)', 'n')
        nnoremap <buffer> <leader>cO <cmd>call jukit#cells#create_above(0)<cr>
    endif
    if !hasmapto('jukit#cells#create_below(1)', 'n')
        nnoremap <buffer> <leader>ct <cmd>call jukit#cells#create_below(1)<cr>
    endif
    if !hasmapto('jukit#cells#create_above(1)', 'n')
        nnoremap <buffer> <leader>cT <cmd>call jukit#cells#create_above(1)<cr>
    endif
    if !hasmapto('jukit#cells#merge_above', 'n')
        nnoremap <buffer> <leader>cM <cmd>call jukit#cells#merge_above()<cr>
    endif
    if !hasmapto('jukit#cells#merge_below', 'n')
        nnoremap <buffer> <leader>cm <cmd>call jukit#cells#merge_below()<cr>
    endif
    if !hasmapto('jukit#cells#move_up', 'n')
        nnoremap <buffer> <leader>ck <cmd>call jukit#cells#move_up()<cr>
    endif
    if !hasmapto('jukit#cells#move_down', 'n')
        nnoremap <buffer> <leader>cj <cmd>call jukit#cells#move_down()<cr>
    endif
    if !hasmapto('jukit#cells#delete_outputs(0)', 'n')
        nnoremap <buffer> <leader>ddo <cmd>call jukit#cells#delete_outputs(0)<cr>
    endif
    if !hasmapto('jukit#cells#delete_outputs(1)', 'n')
        nnoremap <buffer> <leader>dda <cmd>call jukit#cells#delete_outputs(1)<cr>
    endif
    if !hasmapto('jukit#cells#jump_to_next_cell', 'n')
        nnoremap <buffer> <leader>J <cmd>call jukit#cells#jump_to_next_cell()<cr>
    endif
    if !hasmapto('jukit#cells#jump_to_previous_cell', 'n')
        nnoremap <buffer> <leader>K <cmd>call jukit#cells#jump_to_previous_cell()<cr>
    endif

    " ipynb conversion
    if !hasmapto('jukit#convert#notebook_convert("jupyter-notebook")', 'n')
        nnoremap <buffer> <leader>np <cmd>call jukit#convert#notebook_convert("jupyter-notebook")<cr>
    endif
    if !hasmapto("jukit#convert#save_nb_to_file(0,1,'html')", 'n')
        nnoremap <buffer> <leader>ht <cmd>call jukit#convert#save_nb_to_file(0,1,'html')<cr>
    endif
    if !hasmapto("jukit#convert#save_nb_to_file(0,1,'pdf')", 'n')
        nnoremap <buffer> <leader>pd <cmd>call jukit#convert#save_nb_to_file(0,1,'pdf')<cr>
    endif
    if !hasmapto("jukit#convert#save_nb_to_file(1,1,'html')", 'n')
        nnoremap <buffer> <leader>rht <cmd>call jukit#convert#save_nb_to_file(1,1,'html')<cr>
    endif
    if !hasmapto("jukit#convert#save_nb_to_file(1,1,'pdf')", 'n')
        nnoremap <buffer> <leader>rpd <cmd>call jukit#convert#save_nb_to_file(1,1,'pdf')<cr>
    endif
endfun

if type(g:jukit_mappings_ext_enabled) == 1
    let g:jukit_mappings_ext_enabled = [g:jukit_mappings_ext_enabled]
endif
if index(g:jukit_mappings_ext_enabled, '*') >= 0
    let s:jukit_mappings_ext_aupat = '*'
else
    let s:jukit_mappings_ext_aupat = '*.' . join(g:jukit_mappings_ext_enabled, ',*.')
endif

if g:jukit_mappings == 1
    exe "autocmd BufEnter " . s:jukit_mappings_ext_aupat . " call s:set_mappings()"
endif
