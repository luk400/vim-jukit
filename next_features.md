# todos

- [X] show outhist: remove Cell ID line under "Last Outputs"

- [X] show outhist: currently there's an ascii "frame" (╭───...) only around the "Last Outputs\n Cell ID:..." title. i want the frame to encompass the whole shown history, so it's better distinguished from other output. but don't make a frame on the right side, only on the left. maybe like:
╭────────────➞
│ Last Output
├────────────➞
│
│ This is some example output note it goes beyond the horizontal bars, thats ok
│
│ some other output
│ <fig> here a figure 
│
╰────────────➞
not sure how possible this is, as even figures need to be prepended by this frame on the left. if it's not possible, let's talk about it

- [X] there's an issue where where only ever one plot is visible at a time. why? i.e. if i call plt.plot([1,2,3]);plt.show() twice in a row, the first plot in the pane disappears when the second one is shown - i use the foot terminal btw, in case that matters at all. -> fixed for now be restarting zellij session -> if appears again, use debug scripts in /workspace/jukit_debug_sixel scripts and give AI as context -> The moment you notice "first plot disappeared" again, before doing anything else: Open a fresh shell pane (NOT the IPython output pane) and run: bash /tmp/jukit_debug_sixel/01_raw_two_sixels.sh; If L1 also fails in that fresh pane → it's confirmed grid-wide corruption, the bug is the same one we've been hunting. If L1 works but plt.show() is still broken → there's something specific to the IPython pane, and we'd then run 03/04 in that pane. IMPORTANT: Note the trigger. Right before the bug appeared, what did you do? Common candidates worth being alert to:
    - Pane resize (zellij Ctrl-p +/-)
    - Hide/show pane toggle (<leader>os repeatedly)
    - Crossed N plots in the same pane (count them)
    - A specific cell that produced a particularly large or unusual figure
    - The stale jukit_outhist_eTScEmGXX9 floating pane appearing/disappearing

- [X] displaying plots in outhist on <leader>so results in always the second terminal line after the plot starts being weirdly indented by one empty space (this also obscures one column in line 2 of each plot)
╭──────────────➞
│ Last Output
├──────────────➞
│ <first line of plot...>
  │ <second line of plot weirdly indented for some reason>
│ <third line of plot, normal again...>
│ <...>
  -> fix: emit_image_suffix in helpers/jukit_run/util.py was relying on
     the post-sixel cursor being at col 1, but zellij leaves it at the
     column where the sixel started (col 3, just past the `│ ` prefix).
     `\033[<n>A` cursor-up preserves the column, so iter 1 of the
     prefix-redraw loop wrote its `│ ` at col 3 of row 2 instead of
     col 1. Added a leading `\r` after the cursor-up to snap to col 1.

- [X] make it so <leader>so doesnt run %clear (want to preserver history)
  -> fix: removed the `%clear` call at the top of the `jukit_out_hist`
     magic in helpers/jukit_run/jukit_run.py. The two other `%clear`
     sites (KeyboardInterrupt/BufferError emergency handlers in
     util.py:display_outputs, and the one-shot startup clear in
     splits.vim:227 that nukes the IPython boot banner) are intentional
     and unrelated -- left alone.

- [X] <leader><space> on markdown cell should do the same as <leader>so, i.e. displaying the rendered markdown, not sending it as code to the pane
  -> fix: in autoload/jukit/send.vim, jukit#send#section now detects
     md cells (via the existing is_md_cell + get_current_cell_id) and
     delegates to jukit#splits#show_last_cell_output(1) instead of
     falling through to s:send_single_section. show_last_cell_output
     already has the md branch (zellij-gated, with sixel/rich render);
     no duplication. force=1 skips the same-cell guard so re-renders
     work. On non-zellij backends, the existing show_last_cell_output
     fallthrough prints "No saved output for this cell" instead of
     the broken old behavior of dumping the raw md source into IPython
     as Python code.

- [X] there's a rendering issue when using formulas (rendered by latex) in markdown cells. example cell:
r"""°°°
# new md cell
**this is a new md cell!**
this is a formula: $1+1=2$
°°°"""
this is displayed as follows in the ipython pane:
╭──────────────➞
│ Last Output
├──────────────➞
│                                     new md cell
│
│ this is a new md cell! this is a formula:
<picture of 1+1=2>


╰──────────────➞
so the "│" ascii character is not prepended at the latex rendered formula picture, and for some reason is also missing on the next 2 lines
  -> fix: helpers/jukit_run/render_markdown.py:_emit_png_as_sixel was
     writing the sixel bytes directly to sys.stdout.buffer, bypassing
     the _LinePrefixWriter set up by outhist_frame(). Now duck-types
     sys.stdout for the emit_image_prefix attribute and, when
     present, calls emit_image_prefix() before the sixel and
     emit_image_suffix(cell_rows) after -- the same protocol
     display_outputs uses for code-cell plot sixels in util.py.
     cell_rows is computed from new_h after the same scale logic
     used by sixelcat.cat. Also drops the trailing `\n` when wrapped
     so the cursor lands at "row after image, col 1" which is what
     emit_image_suffix expects (matches the display_outputs protocol).
     The phantom blank lines were the missing-prefix image rows + the
     trailing `\n`; both go away with the bar overlay.

        - [ ] tested by user. still now completely fixed (though better than before):
works mostly now, but i noticed an issue with 2 formulas displayed beneath each other, each resulting formula image 4 terminal rows high. i get this output:
│<start of first img>
│<img content...>
│<img content...>
│<img content...>
│<start of second img>
 <img content - seemingly correctly indented, but ascii character missing at the beginning>
│<img content...>
│<img content...>

here the code that produced it:
```
$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

$$
\mathbf{A} = \begin{bmatrix} a & b \\ c & d \end{bmatrix}
$$
```
if i add another mathbf{A} = ... formula afterwards, i get the issue again: at the second row of the third image i again have a missing ascii character
  -> root cause: zellij's post-sixel cursor advance is
     `move_cursor_down_by_pixels(image_pixel_height / 2)` (per the
     halving in helpers/sixelcat/install_and_patch_zellij.sh). The
     halving + ceil-div introduces rounding drift between back-to-
     back sixel emissions: cursor lands on a row INSIDE the visual
     image rather than below it. emit_image_suffix's cursor-up +
     write loop then drew the bars one row off for image 2+, leaving
     row 2 of every image after the first without a bar.
  -> attempted fix #1: added a new method `emit_image_with_bars(
     image_cell_rows, sixel_bytes)` to _LinePrefixWriter in
     helpers/jukit_run/util.py. It pre-allocates `image_cell_rows`
     rows of `│ ` BEFORE sixel emission, saves the cursor with DECSC
     `\033[s`, emits sixel, restores with DECRC `\033[u`, then
     explicitly cursors down by image_cell_rows and snaps to col 1.
     render_markdown.py:_emit_png_as_sixel now routes through this.
  -> debug logs confirmed cell_rows=4 for both images, but the
     user noticed the matrix takes ONE MORE visual row than the
     integral. Pinned down: the sixel deserializer in zellij
     encodes pixel data in 6-row strips
     (`make_sure_six_lines_exist_after_cursor` rounds up to the
     next multiple of 6). The patches in
     install_and_patch_zellij.sh then halve+double the values
     such that the actual rendered height is `ceil(new_h/6)*6`,
     not `new_h`. So:
       integral 81 px → padded to 84 → ceil(84/22) = 4 cells (= my count)
       matrix    86 px → padded to 90 → ceil(90/22) = 5 cells (= my count + 1!)
     The matrix's 5th visual row was never bar-prefixed because
     I pre-allocated only 4 bars. Apparent randomness was actually
     deterministic per-image-shape, masked by IPython pane fill
     state (when content scrolls, the unprefixed row jumps from
     "below the visible area" to "in the middle of scrollback").
  -> fix #2: in helpers/jukit_run/render_markdown.py
     :_emit_png_as_sixel, compute cell_rows from the
     sixel-padded height instead of new_h:
       sixel_padded_h = ((new_h + 5) // 6) * 6
       cell_rows = ceil(sixel_padded_h / pix_per_row)
     Comment in the code explains the math + the relationship to
     the install_and_patch_zellij.sh patches.
     Also enriched the JUKIT_RENDER_MD_DEBUG log to print both
     `naive_cells` (old broken count) and `cell_rows` (new
     correct count) for future debugging.

- [X] when a markdown cell is rendered (via <leader><space> or <leader>so), change "Last Output" to "Markdown" in the title
  -> fix: parameterized helpers/jukit_run/util.py:display_outhist_header
     and outhist_frame to take a `title` arg (default "Last Output").
     jukit_out_hist in jukit_run.py now passes title="Markdown" when
     args.md is set, "Last Output" otherwise. Removed the now-unused
     _OUTHIST_TITLE_ROW constant.

- [X] figure out why the following fails when trying to render in a markdown cell:
$$
\begin{align}
a = \frac{1}{2} && b = \frac{1}{3} && c = \frac{1}{4} \\
a && b && c
\end{align}
$$
error: [pdflatex render failed: ! Package amsmath Error: Erroneous nesting of equation structures; | (amsmath)                trying to recover with `aligned'. | ]
  -> root cause: helpers/jukit_run/render_markdown.py:_render_via_pdflatex
     unconditionally wraps display math in `\Large \[ ... \]`. amsmath
     environments like `align`, `equation`, `gather`, `multline`,
     `flalign`, `alignat` (and their starred variants) ALREADY open
     display math mode by themselves. Wrapping them in `\[ \]` produces
     `\[ \begin{align} ... \end{align} \]`, which is what amsmath
     reports as "Erroneous nesting of equation structures; trying to
     recover with `aligned'".
  -> fix: added module-level regex `_TOP_LEVEL_MATH_ENV_RE` matching the
     known top-level display-math environments (align, equation,
     gather, multline, eqnarray, flalign, alignat, xalignat, xxalignat,
     displaymath, math; with optional `*` star). When math_src begins
     with one of those, _render_via_pdflatex now emits `\Large\n` +
     math_src directly at document top level (no `\[ \]` wrap).
     Everything else (plain math, `aligned`, `bmatrix`, `cases`,
     matrix family, etc.) still gets the existing wrapper. \Large is
     a font-size declaration that propagates into the inner math
     environment, so the visual size matches other display math.
     Verified by running pdflatex on a battery of 14 cases (8
     top-level envs, 3 wrap-required envs, 3 plain regression
     checks) -- all compile cleanly.

- [X] look at the logic of sending codecells to the pane with <leader><space> -> it hides the "In [x]: ..." prompts after sending code to the pane (s.t. only the most current "In [x]:" is displayed, and the past ones are hidden. this is currently only done for code cells. i want this also done in the same way for when markdown cells are rendered, or when history of either code or markdown cells is shown via <leader>so! (i.e., do for %jukit_out_hist the same hiding logic as is currently done for %jukit_run)
  -> fix: jukit_run already calls util.hide_prompt(self.shell) in
     helpers/jukit_run/jukit_run.py (line 254, gated on `-p` opt). It's
     a tiny ANSI sequence: `\033[A` + spaces + `\033[A` -- erase the
     `In [N]: %jukit_run ...` echo line and leave the cursor at col 1
     of that row, ready for the next content. Combined with the
     `monitor_excount_dec` decorator (which restores execution_count
     after the call), the In counter never advances and there's only
     one `In [x]:` visible at the bottom of the pane.
  -> %jukit_out_hist now does the same thing: added an unconditional
     `util.hide_prompt(self.shell)` call right after argument parsing
     and BEFORE the outhist_file existence check. The erased prompt
     row visually merges with outhist_frame's leading blank line, so
     the cyan top border lands cleanly without an extra empty row.
     Both pathways are covered by the single change:
       - <leader>so          → show_last_cell_output → %jukit_out_hist
       - <leader><space> on md cell (zellij) → show_last_cell_output
         → %jukit_out_hist --md
     so code-cell history, code-cell <leader><space> (already worked),
     md cell <leader>so, and md cell <leader><space> all now hide
     their In prompts identically.

- [X] when i do <leader>all or <leader>cc, the markdown cells are skipped. i'd like to change that s.t. the markdown cells are also rendered, not just the code cells
  -> root cause: helpers/jukit_run/jukit_run.py:jukit_run had
     `if "md_cell_start" in opts and cmd.strip().startswith(...): return`
     -- a hard skip for any cell whose source begins with the md
     marker. The skip was set up by autoload/jukit/send.vim's
     until_current_section / all, which always passed
     `--md_cell_start=r"""°°°` so jukit_run_split could iterate over
     every cell and let jukit_run drop the markdown ones on the
     floor.
  -> fix: replace the skip with the same render path that
     `%jukit_out_hist --md` uses (added in the previous outhist
     work):
       1. Added module-level helper `_extract_md_source(cmd, md_start,
          md_end)` in jukit_run.py that strips the leading
          `r"""°°°` and trailing `°°°"""` markers from a cell's
          source. Defensive: returns None if md_start prefix isn't
          there, returns body as-is if md_end is missing (cell has
          no closing marker), preserves embedded markers (`r"""°°°`
          inside body, `°°°"""` not at the end).
       2. jukit_run now also accepts `md_cell_end=` in
          parse_options. When the md_cell_start match fires, it
          extracts the body via _extract_md_source and renders it
          inside `outhist_frame(title="Markdown")` via the same
          `render_markdown_cell(...)` call jukit_out_hist's md
          branch uses, then returns. show_latex_warning is read
          from .jukit_info.json the same way.
       3. Gating: `md_cell_end` is the implicit "render md cells"
          gate. If it's NOT in opts, the old skip behavior runs
          unchanged. send.vim only attaches it on zellij (the only
          backend with the sixelcat math pipeline) so other
          backends don't dump unrendered sixel into the pane.
       4. send.vim: factored the lang_info / md_args building into
          a new s:md_args() helper used by both
          until_current_section and all. The helper conditionally
          appends `--md_cell_end=` only when g:jukit_terminal ==
          'zellij'. Both functions also now pass the param dict
          even in the !g:jukit_save_output branch (previously they
          dropped it, which was a latent bug -- the existing skip
          behavior also didn't fire for save_output=0).
  -> verified _extract_md_source via standalone smoke test (8
     cases): leading/trailing whitespace, empty cell, embedded
     start/end markers, missing closing marker, math content,
     non-md cell returning None, surrounding whitespace. All pass.
  -> follow-up: <leader>cc and <leader>all on a file containing
     a mix of code and md cells now produce: green `In` boxes for
     code cells (existing path) and cyan `Markdown` outhist
     frames for md cells (new path), with bar prefixes around
     math sixels and matching the visual style of <leader>so /
     <leader><space>.

- [X] for some reason the background color in markdown cells is scuffed when displaying .py files in nvim. the markdown syntax is all shown correclty with correct syntax highlighting, but the background signs are sometimes not shown at all and sometimes only part way through the markdown cell. see if you find any brittle/erroneous logic for this in the plugin
  -> root cause #1 (the main one): autoload/jukit.vim's
     s:add_signs_in_region built its sign list with `id: l`, where
     `l` is the array INDEX into the per-cell `range(line('.'), num_end)`
     (so 0, 1, 2, ...). vim signs are keyed by (group, id, buffer),
     and sign_placelist UPDATES an existing key rather than creating a
     new sign. With multiple md cells in the buffer, the second cell's
     ids 0..N-1 silently moved the signs the first cell had just
     placed at those same ids. With cells of unequal length the first
     cell would lose its leading rows but keep its trailing ones (the
     ids that the shorter second cell didn't reach), which is exactly
     the user's "sometimes only part way through" symptom. Fix: use
     `id: v` (the absolute line number) so every sign across all
     cells has a unique id.
  -> root cause #2 (the cross-buffer one): the line-count cache
     variables `s:textcell_nlines` / `s:markers_nlines` were
     SCRIPT-local. Switching from a 100-line buffer to another
     100-line buffer made the early-return fire (`line('$') ==
     s:textcell_nlines`), so the new buffer's md backgrounds were
     never placed. Fix: store the cache as buffer-local
     `b:jukit_textcell_nlines` / `b:jukit_markers_nlines`, gated on
     `exists()` for the first call per buffer.
  -> NOT touched: the early-return on line-count alone misses
     edits that move content between md cells without changing the
     total buffer length (e.g. add 2 lines to cell A, remove 2 from
     cell B). This is rare and the fix would require tracking each
     cell's range, not just the buffer line count -- left for later.
  -> verification: traced the bug end-to-end with the example "cell A
     6 lines, cell B 4 lines": with the old `id: l` code cell A loses
     ids 0..3 (overwritten by cell B's 4 entries) but keeps ids 4..5
     pinned to its lines 9..10 -> partial highlight on cell A, full
     highlight on cell B. With `id: v` every line has a unique id and
     no overwrite happens. No live nvim was available on the host so
     the fix is by analysis + matching the user's reported symptom
     pattern; user should restart nvim and confirm.

- [ ] make it so default session names are not some random uid, but just empty -> the user has to name them explicitely (either when running <leader>os for the first time, or when running <leader>ss and selecting new session), then we just check whether there's already a session with that name activate and display a message for the user to choose a different name 

- [ ] need a way within nvim to increase/decrease zellij pane width

- [ ] currently there seems to be a bug when g:jukit_output_float=1, where when pressing <leader>os there flashes a floating window very very briefly (like fractions of a second) of what seems like an outhist floating window that might be leftover from an old implementation

- [ ] when user does <leader>ss, it should not just show active sessions and the create new... option, but also a load previous option, which if selected, gives the user a list of sessions for which outputs are saved in .jukit (in a floating window dialog), when the user selects one, the session is named like the selected one and user can show outputs from that session (of course he needs to rerun the cells, but atleast the outputs are present from the old session, maybe display a short message stating this after loading a session)

- [ ] when user does <leader>np to convert .py file to .ipynb and he wants to also copy over outputs to the .ipynb, he should specify from a floating dialog with a list of saved session names which session output should be put in the notebook

- [ ] when user does <leader>np to convert a .ipynb file to a .py file, he should specify a session name under which to save the outputs of the .ipynb file (if it has any) - default to the name _original_outputs_converted_ here

- [ ] if the user uses zellij, we could theoretically preserve sessions even across different nvim sessions. i.e. user closes nvim -> leave zellij sessions running in the background, do not kill them -> user sometime later opens the .py file again -> reconnect and continue with existing zellij sessions, i.e. they immediately show up in <leader>ss again.

- [ ] remove support for überzug, iterm, kitty, tmux, etc. completely. only support zellij, vimterm, nvimterm from now on. this makes the plugin much more maintainable.

