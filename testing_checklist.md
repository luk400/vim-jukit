# vim-jukit zellij testing checklist

Walk through this end-to-end inside a fresh zellij session. Each item is a
single observable thing to verify. Tick the box once you've confirmed it.

The intended order matters: later sections assume earlier sections work.
If something breaks, stop and report so we can fix it before running the
later items (otherwise the later failures will be confusing).

## Pre-flight

- [ ] You're inside a zellij session (`echo $ZELLIJ` is non-empty).
- [ ] `which img2sixel` returns a path
- [ ] You have a sixel-capable terminal
- [ ] Open a `.py` file with at least 3 cells, each containing some code
- [ ] `:echo g:jukit_terminal` is `'zellij'`
- [ ] `:messages` after vim startup is clean — no red errors

## Output pane — basic creation flow

- [ ] `<leader>os` opens a session-name input prompt (a centered
      floating window).
- [ ] Pressing `Esc` or entering an empty name cancels with the message
      `[vim-jukit] session creation cancelled`. Nothing is created.
- [ ] `<leader>os`, type a name like `main`, press Enter → an output pane
      appears in your zellij tab, in the direction of
      `g:jukit_zellij_output_direction` (default: right of vim).
- [ ] `ipython3` starts in the new pane. You should see the ipython
      prompt appear within ~2s.
- [ ] **No second pane (outhist) is created** — only the single output
      pane.
- [ ] `:messages` after this is clean (no errors).
- [ ] `:echo b:jukit_active_session` returns `0`.
- [ ] `:echo b:jukit_sessions[0]` shows a dict with `name='main'`,
      non-empty `output_title`, non-empty `output_pane_id`,
      `output_visible=1`. **No `outhist_*` fields should be present.**

## Sending code

- [ ] Move the cursor to a line containing `print("hello")` and press
      `<enter>` → `hello` appears in the output pane.
- [ ] Visually select a multi-line snippet and press `<enter>` →
      the snippet runs in ipython, output appears.
- [ ] Move cursor onto a code cell and press `<leader><space>` →
      the entire cell runs.
- [ ] Press `<leader>cc` from inside a cell → all cells from the start
      up to (and including) the current cell run.
- [ ] Press `<leader>all` from anywhere → all cells in the file run.
- [ ] After all of the above, the output in the pane is correct and
      none of these print `[vim-jukit] No split window found`.

## Output pane — toggle visibility

- [ ] With output pane visible, press `<leader>os` again. The pane
      hides.
- [ ] `:echo b:jukit_sessions[0].output_visible` is `0` after hiding.
- [ ] Press `<enter>` on a code line while the pane is hidden →
      the code still executes (write-chars works on hidden panes).
- [ ] Press `<leader>os` again → the pane comes back visible.
- [ ] `:echo b:jukit_sessions[0].output_visible` is `1` after showing.
- [ ] In the now-visible pane, the previous `<enter>`'s output is
      already in the scrollback (sent while hidden).

## Output pane — close

- [ ] Press `<leader>od` → the output pane closes entirely.
- [ ] `:echo b:jukit_sessions[0].output_visible` is `-1`.
- [ ] `:echo b:jukit_sessions[0].output_pane_id` is empty `''`.
- [ ] `<enter>` on a code line now prints `[vim-jukit] No split window
      found`.
- [ ] `<leader>os` recreates the pane.

## Inline cell-output rendering (`<leader>so`)

- [ ] With an output pane open, run a cell that produces text output
      (e.g. `print("hello world")`).
- [ ] Move the cursor to that cell and press `<leader>so` → the output
      pane clears its visible screen, shows a cyan unicode-box header
      with the cell ID, and prints `hello world` below it.
- [ ] Scroll up in the output pane (e.g. zellij scroll mode) — your
      previous live execution output is still in the scrollback.
- [ ] Move the cursor to a different cell and press `<leader>so` again →
      the screen clears and the new cell's saved output renders.
- [ ] Press `<leader>so` on a cell that has no saved output → magenta
      `No saved output for this cell` message.
- [ ] Press `<leader>so` on the same cell twice in a row → the second
      press is a no-op (redundancy guard via `g:jukit_outhist_last_cell`).

## Inline cell-output rendering — image plots

- [ ] Run a cell with a matplotlib plot:
      `import matplotlib.pyplot as plt; plt.plot([1,2,3]); plt.show()`
      The plot renders inline in the output pane (live, via sixelcat).
- [ ] `<leader>so` on that cell → the screen clears and the saved plot
      re-renders inline (via the same sixel pipeline).
- [ ] Plot is a reasonable size (not full-screen, not microscopic).
      `g:jukit_sixelcat_width_factor` (default 1.8) controls this.

## Output pane page-scroll (`<leader>j` / `<leader>k`)

- [ ] Run several cells producing text output so the output pane has
      scrollable content.
- [ ] Press `<leader>k` → the output pane scrolls up by one page.
- [ ] Press `<leader>j` → the output pane scrolls back down by one page.

## Multi-session — picker UI

- [ ] With one session active (`main`), press `<leader>ss` → the
      session picker (a centered floating window) appears, listing
      `main (active)` and `Create new...`.
- [ ] Press `<Esc>` → cancels, no message.
- [ ] `<leader>ss` again → pick `main` (already active) → no-op.
- [ ] `<leader>ss` again → pick `Create new...` → second prompt for
      the new session name. Enter `experiment`.
- [ ] `:echo len(b:jukit_sessions)` is now `2`.
- [ ] `:echo b:jukit_active_session` is `1` (the new one).
- [ ] If `main` had an output pane visible, `experiment` should
      auto-spawn its own output pane in the same position.

## Multi-session — switch and visibility-mirror

- [ ] `<leader>ss` → picker now lists `experiment (active)`, `main`,
      `Create new...`. Pick `main`.
- [ ] `experiment`'s output pane hides; `main`'s output pane re-appears
      (or is recreated if it was closed earlier).
- [ ] In `main`'s ipython, define `marker_in_main = 1`.
- [ ] `<leader>ss`, pick `experiment` again. In `experiment`'s ipython,
      `print(marker_in_main)` raises `NameError` — confirms the two
      sessions are independent ipython processes.
- [ ] In `experiment`'s ipython, define `marker_in_experiment = 42`.
- [ ] `<leader>ss`, pick `main` → `print(marker_in_main)` still works
      (state preserved across switch).
- [ ] **Verify the layout is unchanged** after the switch — vim left,
      output right (the bug from the previous iteration where outhist
      ended up next to vim should be impossible to reproduce because
      there's no second pane to displace).

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

- [ ] In a fresh vim session, `:let g:jukit_output_float = 1` (or set
      it in your config).
- [ ] `<leader>os` → output pane appears as a **floating** zellij pane,
      not a tiled one.
- [ ] `<leader>os` again → the floating layer hides.
- [ ] `<leader>os` once more → the floating layer comes back.
- [ ] `<leader>so` on a cell with saved output → the magic still runs,
      cell renders inside the floating pane.

## Resize function (optional)

- [ ] With output pane visible,
      `:call jukit#zellij#layouts#resize_output('increase', 5)` →
      output pane visibly grows by ~25% (5 × ~5% per zellij resize bump).
- [ ] `:call jukit#zellij#layouts#resize_output('decrease', 5)` →
      returns to roughly its original size.

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
      `[vim-jukit] g:jukit_output_float is only supported on zellij; ...`
      And `:echo g:jukit_output_float` is `0` after startup.
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
      line. `<leader>so` renders a saved cell inline. `<leader>od`
      closes.
- [ ] **nvimterm** (neovim only): same as vimterm but in nvim.

If any of these breaks, the regression is most likely from the
cross-backend `show_last_cell_output` rewrite or the per-backend
`out_hist_scroll` repurposing. Report which backend and which step.

## Negative checks (deleted features)

These should NOT exist after the refactor:

- [ ] `:map <leader>hs` prints `No mapping found`.
- [ ] `:map <leader>ohs` prints `No mapping found`.
- [ ] `:map <leader>hd` prints `No mapping found`.
- [ ] `:map <leader>ohd` prints `No mapping found`.
- [ ] `:map <leader>ah` prints `No mapping found`.
- [ ] `:JukitOutHist` does not exist as a command.
- [ ] No `helpers/jukit_outhist_view.py` file at the repo root.
- [ ] No `autoload/jukit/ueberzug.vim` file.
- [ ] No `helpers/ueberzug_output/` directory.
- [ ] `:echo exists('g:jukit_auto_output_hist')` returns `0`.
- [ ] `:echo exists('g:jukit_outhist_float')` returns `0`.
- [ ] `:echo exists('g:jukit_zellij_outhist_direction')` returns `0`.
- [ ] `:echo exists('g:jukit_hist_use_ueberzug')` returns `0`.

## Smoke test

- [ ] From inside a zellij session, in vim: `:call
      jukit#tests#run_test('zellij_smoke', 0)` → runs the automated
      smoke test (output → close output).
      The result is written to `tests/jukit_tests_summary.json`. Open
      that file and confirm the `zellij_smoke` entry is `[1, ""]`.

## Cleanup

- [ ] Close any zellij panes left over from testing manually.
- [ ] Quit vim cleanly. Since 2026-04, the QuitPre autocmd persists
      session state to .jukit/ but does NOT close panes -- they outlive
      vim so the next session can reconnect. Use `<leader>ss` →
      `Kill all sessions` to actively close them.

---

**If anything fails**: stop and report which item, with a copy of any
red error messages from `:messages` and the output of `:echo
b:jukit_active_session` and `:echo b:jukit_sessions` so I can see the
state.
