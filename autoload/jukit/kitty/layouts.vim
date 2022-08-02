let s:layout_kitten = jukit#util#plugin_path() . g:_jukit_ps . 'helpers' . g:_jukit_ps . 'layout_kitten.py'

fun! jukit#kitty#layouts#set_layout(layout) abort
    let args = ['kitten', s:layout_kitten, json_encode(a:layout)]
    if jukit#kitty#splits#exists('output')
        call add(args, json_encode({'output': g:jukit_output_title}))
    endif
    if jukit#kitty#splits#exists('outhist')
        call add(args, json_encode({'output_history': g:jukit_outhist_title}))
    endif
    let response = call('jukit#kitty#cmd#kitty_command', args)
    if type(response) == 7
        echom "[vim-jukit] Note: If RESPONSE contains a file-not-found error, "
            \ . "it might be due to kitty converting '-' to '_' in the "
            \ . "plugin-path. Please update kitty to a newer "
            \ . "version where this has been fixed!"
    endif
endfun
