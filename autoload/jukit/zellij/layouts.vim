" Zellij has no clean absolute-sizing API: the only resize primitive is
" `zellij action resize increase|decrease <dir>`, which adjusts by an
" implementation-defined step (~5%). That means we can't honor the
" proportions in g:jukit_layout the way the (n)vimterm backends can.
"
" Rather than pretend to support layouts, we accept zellij's defaults at
" pane creation time and expose an increase/decrease helper below for
" users who want to nudge the output pane width interactively.

let s:inverse_direction = {
    \ 'right': 'left',
    \ 'left':  'right',
    \ 'up':    'down',
    \ 'down':  'up',
    \ }

fun! jukit#zellij#layouts#set_layout(layout) abort
    " Intentional no-op. See README "Zellij" section for the rationale and
    " for jukit#zellij#layouts#resize_output (the user-facing knob that
    " DOES work).
endfun

" Resize the jukit output pane by `steps` (default 5) zellij resize-bumps,
" growing or shrinking it along the axis it shares with the vim pane.
" `action` is 'increase' or 'decrease'.
fun! jukit#zellij#layouts#resize_output(action, ...) abort
    let session = jukit#zellij#splits#_active_session()
    if type(session) == type(v:null) || empty(session.output_pane_id)
        echom '[vim-jukit] No output pane to resize'
        return
    endif
    let steps = a:0 > 0 ? a:1 : 5
    " The "interesting" edge of the output pane is the one facing vim,
    " which is the inverse of the direction we created the pane in.
    let resize_dir = get(s:inverse_direction, g:jukit_zellij_output_direction, 'left')
    for i in range(steps)
        call jukit#zellij#cmd#zellij_command(
            \ 'resize', '--pane-id', session.output_pane_id, a:action, resize_dir)
    endfor
endfun
