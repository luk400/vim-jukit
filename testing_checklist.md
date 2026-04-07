# vim-jukit zellij testing checklist

Walk through this end-to-end inside a fresh zellij session. Each item is a
single observable thing to verify. Tick the box once you've confirmed it.

The intended order matters: later sections assume earlier sections work.
If something breaks, stop and report so we can fix it before running the
later items (otherwise the later failures will be confusing).

## Pre-flight

- [X] You're inside a zellij session (`echo $ZELLIJ` is non-empty).
- [X] `which img2sixel` returns a path
- [X] You have a sixel-capable terminal 
- [X] Open a `.py` file with at least 3 cells, each containing some code
- [X] `:echo g:jukit_terminal` is `'zellij'` 
- [X] `:messages` after vim startup is clean — no red errors

## Output pane — basic creation flow

- [X] `<leader>os` opens a session-name input prompt at the bottom of vim.
    - NOTE from me: i don't like this current input method from a ux perspective. i wanna use floating windows. looks way nicer. please clone my other plugin luk400/vibi.nvim on github, and look how i did input dialogs there when calling :Vibe and enter a "Session Name". i want it the same way in this plugin 
- [X] Pressing `Esc` or entering an empty name cancels with the message
      `[vim-jukit] session creation cancelled`. Nothing is created.
- [X] `<leader>os`, type a name like `main`, press Enter → an output pane
      appears in your zellij tab, in the direction of
      `g:jukit_zellij_output_direction` (default: right of vim).
- [X] The pane title in zellij's frame shows `jukit_output_<random>`.
    - NOTE from me: can't say because i have disabled showing titles in my config. let's just assume it works for now
- [X] `ipython3` starts in the new pane. You should see the ipython
      prompt (or whatever your shell command is) appear within ~2s.
- [X] `:messages` after this is clean (no errors).
- [X] `:echo b:jukit_active_session` returns `0`.
- [X] `:echo b:jukit_sessions[0]` shows a dict with `name='main'`,
      non-empty `output_title`, non-empty `output_pane_id`,
      `output_visible=1`, `outhist_visible=-1`.
    - NOTE from me: it shows this: {'output_pane_id': 'terminal_10', 'outhist_visible': -1, 'output_title': 'jukit_output_W1v6jKJ71k', 'last_used': 1775592165, 'name': 'my_session_name', 'outhist_title': 'jukit_outhist_W1v6jKJ71k', 'output_visible': 1, 'outhist_pane_id': ''}

## Sending code

- [X] Move the cursor to a line containing `print("hello")` and press
      `<enter>` → `hello` appears in the output pane.
- [X] Visually select a multi-line snippet and press `<enter>` →
      the snippet runs in ipython, output appears.
- [X] Move cursor onto a code cell and press `<leader><space>` →
      the entire cell runs.
- [X] Press `<leader>cc` from inside a cell → all cells from the start
      up to (and including) the current cell run.
- [X] Press `<leader>all` from anywhere → all cells in the file run.
- [X] After all of the above, the output in the pane is correct and
      none of these print `[vim-jukit] No split window found`.

## Output pane — toggle visibility

- [~] With output pane visible, press `<leader>os` again. The pane
      hides. (In tiled mode it briefly round-trips through the floating
      layer; the float layer toggles. In float mode, the float layer
      just hides.)
     - NOTE from me: works with split windows. floating windows has weird behaviour. first of all, when i open a .py file and press <leader>os, i can briefly see the floating output window, but only for a fraction of a second, then it disappears. i have to press <leader>os then twice again, then it finally shows and stays where it is. but it is centered in the center of the window. not on the right side like a split pane. also, whenever i click back to my .py file buffer, the floating window auto-hides again. sending code to it seems to work though, as when i toggle it visible again by pressing <leader>os twice i see the code executed. also after it auto-hides when clicking into the code file, :echo b:jukit_sessions[0].output_visible returns still 1 even though the floating pane is not visible. then i press <leader>os, then it returns 0 as expected. then i press it again and it shows it again.
- [X] `:echo b:jukit_sessions[0].output_visible` is `0` after hiding.
- [X] Press `<enter>` on a code line while the pane is hidden →
      the code still executes (write-chars works on hidden panes).
- [X] Press `<leader>os` again → the pane comes back visible.
    - NOTE from me: (as mentioned before this works,but scuffed for floating setting)
- [X] `:echo b:jukit_sessions[0].output_visible` is `1` after showing.
- [X] In the now-visible pane, the previous `<enter>`'s output is
      already in the scrollback (sent while hidden).

## Output pane — close

- [X] Press `<leader>od` → the output pane closes entirely.
- [X] `:echo b:jukit_sessions[0].output_visible` is `-1`.
- [X] `:echo b:jukit_sessions[0].output_pane_id` is empty `''`.
- [X] `<enter>` on a code line now prints `[vim-jukit] No split window
      found`.
- [X] `<leader>os` recreates the pane (no name prompt — you stay in the
      same session).
      - NOTE from me: yes, but this shouldnt be the behaviour though. user should be prompted for a name again!

## Output history (outhist) viewer

- [X] With an output pane open, run a cell that produces text output
      (e.g. `print("hello world")`).
- [~] Press `<leader>hs` → an outhist viewer pane appears in the direction
      of `g:jukit_zellij_outhist_direction` (default: down from output).
      - NOTE from me: works with split window mode. for floating window mode, nothing happens. i quickly see the output window that was (wrongly) hidden flash visible again before immediately disappearing again, then in messages i see: [vim-jukit] Output-history split not found. Please create if first. can only test the rest of this section for the floating setting after a fix is applied!
- [X] The outhist pane shows the cyan `[vim-jukit] outhist viewer ready`
      message.
- [X] `:echo b:jukit_sessions[0].outhist_pane_id` is non-empty.
- [X] Move the cursor to the cell with `print("hello world")` and press
      `<leader>so` → the outhist pane shows a unicode-box header with the
      cell ID and `hello world` underneath.
- [X] Move the cursor to a different cell and press `<leader>so` again →
      the outhist pane re-renders with the new cell's content (clears
      the previous cell first).
- [X] Press `<leader>so` on a cell that has no saved output → the outhist
      pane shows a magenta `no saved output for this cell` message.

## Output history — image rendering (requires img2sixel + sixel terminal)

- [X] Run a cell with a matplotlib plot:
      `import matplotlib.pyplot as plt; plt.plot([1,2,3]); plt.show()`
      The plot renders inline in the *output* pane.
    - NOTE from me: can not test for floating setting yet until issue from previous section is fixed
- [X] `<leader>so` on that cell → the plot also renders in the *outhist*
      pane (via sixelcat through the new viewer's img2sixel pipeline).
- [X] Plot is a reasonable size (not full-screen, not microscopic).
      `g:jukit_sixelcat_width_factor` (default 1.8) controls this; bumping
      it up should make plots wider.
- [X] If `img2sixel` is missing or your terminal doesn't speak sixel, the
      outhist pane shows a red `img2sixel not found` line *or* nothing
      visible — but no crash.

## Output history — auto-update

- [X] Press `<leader>ah` → message `Enabled auto output history!`.
    - NOTE from me: in the future, i want a way to also render markdown cells (though first we need to fix bugs and other issues, this is just a nice to have for way later)
- [X] Move the cursor between cells without pressing anything else.
      After `updatetime` ms (default 4s, set `:set updatetime=1000` for
      faster testing), the outhist pane auto-updates to the cell under
      the cursor.
- [X] Press `<leader>ah` again → message `Disabled auto output history!`.

## Output history — scroll & close

- [X] Run several cells with output, then `<leader>so` on each.
- [X] Press `<leader>j` → outhist pane scrolls down.
- [X] Press `<leader>k` → outhist pane scrolls up.
    - NOTE from me: yes it does, but it also scrolls back through the terminal scrollback to earlier cell output displays? this shouldnt be possible -> you should only be able to plot to the beginning of the current cell history output, not beyond that to old shown outputs!
- [X] Press `<leader>hd` → outhist pane closes cleanly. The viewer
      receives `quit` over its stdin first, then `close-pane` via id.
- [X] `:echo b:jukit_sessions[0].outhist_visible` is `-1` after close.
- [X] `<leader>hs` recreates it.

## Output + history — combined operations

- [X] Press `<leader>ohs` from a buffer with no panes → name prompt,
      enter name, both output and outhist panes appear.
- [X] Press `<leader>ohd` → confirmation prompt → confirm → both panes
      close together.

## Multi-session — picker UI

- [X] With one session active (`main`), press `<leader>ss` → numbered
      picker appears at the bottom of vim:
      ```
      [vim-jukit] Select session:
      1. main (active)
      2. Create new...
      ```
    - NOTE from me: works currently, but this should also be nicer, and instead be an nvim floating window where the user can select session or create new!
- [X] Press `0` or Esc → cancels, no message.
- [X] Press `1` → picks `main` (already active) → no-op, no error.
- [X] Press `2` → picks "Create new..." → second prompt for the new
      session name. Enter `experiment`.
- [X] `:echo len(b:jukit_sessions)` is now `2`.
- [X] `:echo b:jukit_active_session` is `1` (the new one).
- [X] The previously-visible panes (from `main`) are now **hidden** —
      `experiment` has no panes yet.
    - NOTE from me: yes, experiment has no panes yet, but behaviour should be different: after hiding the olds panes, immediately create the new ones (depending on what was shown previously (if both output and outhis previously shown, also immediately spawn them for experiment session; if there is no previous session, only create output split)

## Multi-session — populate the new session

- [X] `<leader>os` (no prompt this time, since active session exists
      with no output) → creates output pane for `experiment`.
- [X] `<leader>hs` → creates outhist pane for `experiment`.
- [X] Run a cell — output goes to `experiment`'s ipython, not `main`'s.
- [X] Define a variable that doesn't exist in `main`, e.g.
      `marker_in_experiment = 42`.

## Multi-session — switch and visibility-mirror

- [X] `<leader>ss` → picker now lists `experiment (active)`, `main`,
      `Create new...` (sorted by last_used desc). Pick `main`.
- [ ] `experiment`'s output and outhist panes hide.
- [ ] `main`'s output and outhist panes appear (or are recreated if
      they were closed earlier).
- [ ] In `main`'s ipython, `print(marker_in_experiment)` raises
      `NameError` — confirms it's a different ipython process.
- [ ] `<leader>ss`, pick `experiment` again. Both panes mirror back.
- [ ] In `experiment`'s ipython, `print(marker_in_experiment)` prints
      `42` — confirms its state was preserved across the switch.

## Multi-session — buffer-local sessions

- [ ] Open a second `.py` file in a new buffer (`:e other.py`).
- [ ] `:echo b:jukit_active_session` returns either `-1` or undefined
      (this buffer has its own fresh session list).
- [ ] `<leader>os` here prompts for a new session name (the previous
      buffer's sessions don't bleed in).
- [ ] Switch back to the first file with `:b#` → `:echo
      b:jukit_active_session` shows the original buffer's active index.
- [ ] `<enter>` on a code line in the first file routes to the first
      file's active session (verify by which pane the output appears in).

## Floating mode

- [ ] In a fresh vim session, `:let g:jukit_output_float = 1` then
      `:let g:jukit_outhist_float = 1` (or set them in your config).
- [ ] `<leader>os` → output pane appears as a **floating** zellij pane,
      not a tiled one.
- [ ] `<leader>os` again → the floating layer hides (your output pane
      disappears along with any other floating panes in the tab — that's
      the documented `hide-floating-panes` global behavior).
- [ ] `<leader>os` once more → the floating layer comes back.
- [ ] `<leader>hs` → outhist also appears as a floating pane.
- [ ] `<leader>os` while in float mode is much smoother than tiled mode
      (no embed-or-floating round-trip).

## Tiled-mode hide/show round-trip caveats

- [ ] With `g:jukit_output_float = 0` (default), `<leader>os` creates a
      tiled output pane.
- [ ] `<leader>os` to hide. **Visually verify** that any unrelated
      floating panes you have in this tab also disappear during the hide
      (this is the documented side effect of the
      `toggle-pane-embed-or-floating` workaround).
- [ ] `<leader>os` to show. The pane should reappear in roughly its
      original tiled position (zellij's behavior; not guaranteed to be
      identical).

## Resize functions

- [ ] With output pane visible, `:call
      jukit#zellij#layouts#resize_output('increase', 5)` → output pane
      visibly grows by ~25% (5 × ~5% per zellij resize bump).
- [ ] `:call jukit#zellij#layouts#resize_output('decrease', 5)` →
      returns to roughly its original size.
- [ ] Same for `resize_outhist('increase'/'decrease', 5)`.
- [ ] If you want to use these often, add the optional keybinds from
      the README's "Resizing panes" subsection to your config.

## State recovery — manual external close

- [ ] With an output pane open, in another shell run:
      ```sh
      zellij action list-panes --json | python3 -c "
      import json,sys
      for p in json.load(sys.stdin):
          if 'jukit_output' in p.get('title',''):
              print(p['id']); break
      " | xargs -I {} zellij action close-pane --pane-id terminal_{}
      ```
- [ ] Back in vim, press `<enter>` on a code line. You may see the
      stale pane briefly (the cache TTL is 200ms) but on the next try
      it should detect the pane is gone, demote `output_visible` to
      `-1`, and print `No split window found`.
- [ ] `<leader>os` then creates a fresh output pane in the same active
      session (no second name prompt).

## Setup-time guards

- [ ] In a fresh vim session: `:let g:jukit_output_float = 1` then
      `:let g:jukit_terminal = 'vimterm'`, restart vim. At startup you
      should see a yellow warning:
      `[vim-jukit] g:jukit_output_float / g:jukit_outhist_float are only
      supported on zellij; got g:jukit_terminal=vimterm. Disabling float
      mode.` And `:echo g:jukit_output_float` is `0` after startup.
- [ ] In zellij, temporarily move `img2sixel` out of `$PATH` (or unset
      `PATH` for the test) and restart vim. You should see:
      `[vim-jukit] img2sixel not found on $PATH; disabling inline
      plotting for zellij.` And `:echo g:jukit_inline_plotting` is `0`.

## Cross-backend regression

These verify that the zellij work didn't break the other backends. Skip
the ones whose backend you don't have installed.

For each backend you can test, set `:let g:jukit_terminal = '<name>'`,
restart vim, then run the basic happy-path checks below.

- [ ] **vimterm**: `<leader>os` opens a vim split. `<enter>` runs the
      line. `<leader>od` closes. `<leader>hs` opens outhist. `<leader>so`
      shows saved output. `<leader>hd` closes.
- [ ] **nvimterm** (neovim only): same as vimterm but in nvim.
- [ ] **kitty** (if you have kitty): same flow.
- [ ] **tmux** (if you have tmux): same flow.

If any of these breaks, the regression is most likely from the
custom-backend precedence change in `autoload/jukit/splits.vim:
_build_shell_cmd` or the BufEnter autocmd. Report which backend and
which step.

## Smoke test

- [ ] From inside a zellij session, in vim: `:call
      jukit#tests#run_test('zellij_smoke', 0)` → runs the automated
      smoke test (output → history → close history → close output).
      The result is written to `tests/jukit_tests_summary.json`. Open
      that file and confirm the `zellij_smoke` entry is `[1, ""]`.

## Cleanup

- [ ] Close any zellij panes left over from testing manually.
- [ ] Quit vim cleanly. The QuitPre autocmd should close any remaining
      jukit panes for the current buffer.

---

**If anything fails**: stop and report which item, with a copy of any
red error messages from `:messages` and the output of `:echo
b:jukit_active_session` and `:echo b:jukit_sessions` so I can see the
state at the failure point.
