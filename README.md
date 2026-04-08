# vim-jukit
## REPL plugin and Jupyter-Notebook alternative for (Neo)Vim

This plugin is aimed at users in search for a REPL plugin with lots of additional features, including but not limited to the following:
* Easily send code to a split window running your preferred shell
* Structure your code with cell markers and use convenient cell operations
* Dedicated markdown cells with markdown syntax
* Seamlessly convert from and to .ipynb notebooks
* Display plots inside the terminal if you're using kitty terminal or iTerm2+tmux and python's matplotlib
* Save outputs of cell executions when using IPython and display saved outputs on demand


## Preview

* **Convert ipynb notebooks to scripts and vice versa**

![convert_from_ipynb_new](https://user-images.githubusercontent.com/57172028/162511857-ceb28439-fbce-4ca0-aae1-1654badf6721.gif)
![convert_to_ipynb_new](https://user-images.githubusercontent.com/57172028/162511912-7f939b1d-d1dc-4099-b345-aca26fa94cae.gif)

* **Cell manipulations: Create, delete, move, split, and merge cells**

![cell_operations_new](https://user-images.githubusercontent.com/57172028/162511802-393e04e3-0837-46a6-add5-10e7764ff38f.gif)

* **Send code to the terminal**

![send_to_terminal_new](https://user-images.githubusercontent.com/57172028/162511988-e9234bde-e421-48ed-9fca-b072357bcc23.gif)

* **Save output from ipython shell and display saved output on demand in dedicated split window**

![output_saving_new](https://user-images.githubusercontent.com/57172028/162511959-d2b9393a-21b1-4781-b415-e07213ab8313.gif)

* **Optionally display saved outputs in terminal as images using [überzug](https://github.com/seebye/ueberzug) instead of printing in split window (experimental)**

![überzug_new](https://user-images.githubusercontent.com/57172028/186850822-4ae0768d-bce7-4718-9f97-174774a34be1.gif)

* **Preview file as pdf, html**

![convert_to_html_pdf_new](https://user-images.githubusercontent.com/57172028/162511885-03675901-c701-4c9e-be41-bb68ef8a2707.gif)

* **For kitty-terminal users: optionally open splits in seperate os-windows** (useful if you have multiple monitors)

![seperate_os_window_new](https://user-images.githubusercontent.com/57172028/162546384-3e4ba886-a6ac-47a3-96e4-5033fd3f8308.gif)

* **For kitty-terminal users (and for iTerm2+tmux users - experimental): in-terminal plotting via matplotlib**

![inline_plotting_new](https://user-images.githubusercontent.com/57172028/162511949-7c521780-a6fb-4a57-b889-7b1e47f5edff.gif)


### Requirements

<details><summary>vim users</summary><p>
&emsp;&#x2022;&nbsp; vim version >= 8.2<br>
&emsp;&#x2022;&nbsp; python3 support (check using `:echo has('python3')`)
</p></details>

<details><summary>neovim users</summary><p>
&emsp;&#x2022;&nbsp; neovim version >= 0.4<br>
&emsp;&#x2022;&nbsp; python3 support (check using `:echo has('python3')`)
</p></details>

<details><summary>(I)Python users</summary><p>
&emsp;&#x2022;&nbsp; ipython version >= 7.3.0<br>
&emsp;&#x2022;&nbsp; matplotlib version >= 3.4.0
</p></details>

<details><summary>kitty terminal users</summary><p>
&emsp;&#x2022;&nbsp; kitty version >= 0.22<br>
&emsp;&#x2022;&nbsp; remote control needs to be enabled in kitty config (i.e. put `allow_remote_control yes` in your kitty.conf), or alternatively you can also always start kitty using `kitty -o allow_remote_control=yes`<br>
&emsp;&#x2022;&nbsp; ImageMagick for displaying plots in the terminal must be installed (install using e.g. `sudo apt-get install imagemagick`)<br>
&emsp;&#x2022;&nbsp; If you're using neovim with kitty, you need to launch kitty with the `--listen-on` option and specify an address to listen on. Furthermore, if you want to have different kitty instances simultaneously using this plugin and sending code to split windows, different addresses will need to be specified. One possible way to do this on linux machines is by simply always starting kitty with e.g. `kitty --listen-on=unix:@"$(date +%s%N)"`, which will make sure different kitty instances are launched with different, abstract sockets to listen on. On MacOS it should work using e.g. `kitty --listen-on=/tmp/kitty_"$(date +%s%N)"`. If you want, you can then simply specify an alias (i.e. put `alias jukit_kitty="kitty --listen-on=unix:@"$(date +%s%N)" -o allow_remote_control=yes"` in your .bashrc/.zshrc) which you can use to always start kitty with the necessary arguments.
</p></details>

<details><summary>iTerm2+tmux users (experimental)</summary><p>
&emsp;&#x2022;&nbsp; currently only tested using iTerm2 Build 3.4.15 + tmux version 3.2a<br>
&emsp;&#x2022;&nbsp; There's a good chance it won't work with a different tmux version. To install the exact version it was tested with, use the following commands:<br>
&emsp;```<br>
&emsp;wget https://raw.githubusercontent.com/Homebrew/homebrew-core/e44425df5a8b3c8c24073486fa7e355f3ac19657/Formula/tmux.rb<br>
&emsp;brew install ./tmux.rb<br>
&emsp;tmux -V # make sure it says tmux 3.2a<br>
&emsp;brew pin tmux # prevent unintentional upgrade in the future<br>
&emsp;```<br>
&emsp;&#x2022;&nbsp; NOTE: I am not a macOS user myself. I've tried to implement inline plotting for iTerm2+tmux and got it working at one point. In case you have problems, feel free to open an issue but be prepared to rely on yourself or others to solve it, since debugging this as a non macOS-user can be time consuming and I have limited time for my open source projects these days.
</p></details>

<details><summary>windows users</summary><p>
&emsp;&#x2022;&nbsp; make sure `python3` - and not just `python` - is a valid command in your terminal, if it's not then set `let g:_jukit_python_os_cmd = 'python'` in your vim config<br>
&emsp;&#x2022;&nbsp; NOTE: I am not a Windows user myself. I've tried to implement a working version for Windows and got it working at one point. In case you have problems, feel free to open an issue but be prepared to rely on yourself or others to solve it, since debugging this as a non Windows-user can be time consuming and I have limited time for my open source projects these days.
</p></details>

<details><summary>überzug users</summary><p>
&emsp;&#x2022;&nbsp; make sure `python3` - and not just `python` - is a valid command in your terminal, if it's not then set `let g:_jukit_python_os_cmd = 'python'` in your vim config<br>
&emsp;&#x2022;&nbsp; required python packages:<br>
&emsp;&emsp; pillow<br>
&emsp;&emsp; beautifulsoup4<br>
&emsp;&emsp; numpy<br>
&emsp;&emsp; nbconvert >= 6.4.4<br>
&emsp;&emsp; ueberzug - NOTE: this package is no longer maintained and available via pip, so it has to be installed manually as follows:<br>
&emsp;&emsp;&emsp;&emsp;```<br>
&emsp;&emsp;&emsp;&emsp;git clone --branch 18.1.9 https://github.com/seebye/ueberzug.git<br>
&emsp;&emsp;&emsp;&emsp;cd ueberzug<br>
&emsp;&emsp;&emsp;&emsp;python3 setup.py install<br>
&emsp;&emsp;&emsp;&emsp;```<br>
&emsp;&#x2022;&nbsp; required CLI tools:<br>
&emsp;&emsp; imagemagick<br>
&emsp;&emsp; cutycapt (alternatively you can also use wkhtmltoimage, if you decide to use wkhtmltoimage, `let g:jukit_ueberzug_cutycapt_cmd = '/path/to/wkhtmltoimage'` has to specified in your vim config)
</p></details>

<details><summary>Zellij with sixelcat</summary><p>
&emsp;&#x2022;&nbsp; libsixel-bin (for `img2sixel`)<br>
&emsp;&#x2022;&nbsp; for inline plotting, zellij currently requires a custom build that fixes some issues with sixel support. You can find my own build script in scripts/install_and_patch_zellij.sh (note: personal build helper, Linux/Debian only, may be stale — see the script header)
</p></details>


### Installation

With your plugin manager of choice, e.g. using vim-plug:

```vim
Plug 'luk400/vim-jukit' 
```

### Issues

If there are any problems, feel free to open an issue. Be sure to include the operating system you're using, your vim or neovim version, python version, your terminal (kitty terminal or otherwise), and possibly relevant jukit-options you've configured. Be sure to try the plugin with an otherwise empty (neo)vim config and see if your problem persists, to narrow down possible conflicts with other settings/plugins that you're using. 

Be aware that I work on this project **for fun** in my free time, so expect that you might not receive any help in a timely manner.

## Usage

### Basic usage in a nutshell (assuming default mappings)

* **Example using ipython:**

If you have an ipynb file containing python code which you first need to convert, simply open it and press `<leader>np`. This will also preseve saved outputs.

In your python file, press `<leader>os` to start an output split.
Now you can start sending code to the shell. Simply press `<enter>` to send the line of the current cursor position to the shell. Visually select code and press `<enter>` to send it to the shell. Press `<leader><space>` to send the code in the current cell to the shell. Only output of cell executions will be saved, ipython outputs from sending single lines or visual selections will not be saved. 

Create a new cell below by pressing `<leader>co`, or `<leader>cO` to create one above. If you want to create a text/markdown cell below, use `<leader>ct`, or `<leader>cT` to create one above. You can also move cells up or down, split cells, or merge cells (see the mappings and explanations below).

Now say you've been coding for a while and want to know what the output of a specific cell was. Instead of searching for it by scrolling up in your shell or completely re-running it (which is often inconvenient for long-running code), you can press `<leader>so` to render the saved output of the current cell inline in the existing output pane. Under the hood this sends `%jukit_out_hist <cell_id>` to the IPython process, which clears the visible screen and re-renders the saved cell output (text + images via the same sixel pipeline that handles live plots). Use `<leader>j` / `<leader>k` to page-scroll the output pane up/down. 

If you want to convert your .py file back to a .ipynb notebook, simply press `<leader>np` again. It'll convert it back and open it using `jupyter-notebook`. 
For all other functions and custimization options, please see the definitions and comments in the next sections.

* **Example using julia (or any other supported language):**

In your (neo)vim config, specify the shell command via `g:jukit_shell_cmd` (e.g. `let g:jukit_shell_cmd='julia'`). If you don't want to specify this in your config because you usually don't work with julia and this is an exception, you can also simply use `:let g:jukit_shell_cmd='julia'` right before opening the output split.
If you have an ipynb file with julia code, simply open it and press `<leader>np`. In the resulting julia file, press `<leader>os` to start an output split.
Now you can start sending code to the shell. Simply press `<enter>` to send the line of the current cursor position to the shell. Visually select code and press `<enter>` to send it to the shell. Press `<leader><space>` to send the code in the current cell to the shell.

Create a new cell below by pressing `<leader>co`, or `<leader>cO` to create one above. If you want to create a text/markdown cell below, use `<leader>ct`, or `<leader>cT` to create one above. You can also move cells up or down, split cells, or merge cells (see the mappings and explanations below).

If you want to convert your .jl file back to a .ipynb notebook, simply press `<leader>np` again. It'll convert it back and open it using `jupyter-notebook`. 
For all other functions and custimization options, please see the definitions and comments in the next sections.

### Options and global variables
For explanations see the comments underneath each variable. Make sure you set these variables in your config somewhere *before* the plugin is loaded.
###### Basic jukit options
```vim
let g:jukit_shell_cmd = 'ipython3'
"    - Specifies the command used to start a shell in the output split. Can also be an absolute path. Can also be any other shell command, e.g. `R`, `julia`, etc. (note that output saving is only possible for ipython)
let g:jukit_terminal = ''
"   - Terminal to use. Can be one of '', 'kitty', 'vimterm', 'nvimterm', 'tmux' or 'zellij'. If '' is given then will try to detect terminal: zellij is detected via `$ZELLIJ`, kitty via window class; otherwise defaults to 'vimterm' or 'nvimterm' (depending on `has("nvim")`).
let g:jukit_use_tcomment = 0
"   - Whether to use tcomment plugin (https://github.com/tomtom/tcomment_vim) to comment out cell markers. If not, then cell markers will simply be prepended with `g:jukit_comment_mark`
let g:jukit_comment_mark = '#'
"   - See description of `g:jukit_use_tcomment` above
let g:jukit_mappings = 1
"   - If set to 0, none of the default function mappings (as specified further down) will be applied
let g:jukit_mappings_ext_enabled = "*"
"   - String or list of strings specifying extensions for which the mappings will be created. For example, `let g:jukit_mappings_ext_enabled=['py', 'ipynb']` will enable the mappings only in `.py` and `.ipynb` files. Use `let g:jukit_mappings_ext_enabled='*'` to enable them for all files.
let g:jukit_notebook_viewer = 'jupyter-notebook'
"   - Command to open .ipynb files, by default jupyter-notebook is used. To use e.g. vs code instead, you could set this to `let g:jukit_notebook_viewer = 'code'`
let g:jukit_convert_overwrite_default = -1
"   - Default setting when converting from .ipynb to .py or vice versa and a file of the same name already exists. Can be of [-1, 0, 1], where -1 means no default (i.e. you'll be prompted to specify what to do), 0 means never overwrite, 1 means always overwrite
let g:jukit_convert_open_default = -1
"   - Default setting for whether the notebook should be opened after converting from .py to .ipynb. Can be of [-1, 0, 1], where -1 means no default (i.e. you'll be prompted to specify what to do), 0 means never open, 1 means always open
let g:jukit_file_encodings = 'utf-8'
"   - Default encoding for reading and writing to files in the python helper functions
```

###### Cell highlighting/syntax
```vim
let g:jukit_highlight_markers = 1
"    - Whether to highlight cell markers or not. You can specify the colors of cell markers by putting e.g. `highlight jukit_cellmarker_colors guifg=#1d615a guibg=#1d615a ctermbg=22 ctermfg=22` with your desired colors in your (neo)vim config. Make sure to define this highlight *after* loading a colorscheme in your (neo)vim config
let g:jukit_enable_textcell_bg_hl = 1
"    - Whether to highlight background of textcells. You can specify the color by putting `highlight jukit_textcell_bg_colors guibg=#131628 ctermbg=0` with your desired colors in your (neo)vim config. Make sure to define this highlight group *after* loading a colorscheme in your (neo)vim config.
let g:jukit_enable_textcell_syntax = 1
"    - Whether to enable markdown syntax highlighting in textcells
let g:jukit_text_syntax_file = $VIMRUNTIME . '/syntax/' . 'markdown.vim'
"    - Syntax file to use for textcells. If you want to define your own syntax matches inside of text cells, make sure to include `containedin=textcell`.
let g:jukit_hl_ext_enabled = '*'
"    - String or list of strings specifying extensions for which the relevant highlighting autocmds regarding marker-highlighting, textcell-highlighting, etc. will be created. For example, `let g:jukit_hl_extensions=['py', 'R']` will enable the defined highlighting options for `.py` and `.R` files. Use `let g:jukit_hl_extensions='*'` to enable them for all files and `let g:jukit_hl_extensions=''` to disable them completely
```

###### Kitty
```vim
let g:jukit_output_bg_color = get(g:, 'jukit_output_bg_color', '')
"    - Optional custom background color of output split window (i.e. target window of sent code)
let g:jukit_output_fg_color = get(g:, 'jukit_output_fg_color', '')
"    - Optional custom foreground color of output split window (i.e. target window of sent code)
let g:jukit_output_new_os_window = 0
"    - If set to 1, opens output split in new os-window. Can be used to e.g. write code in one kitty-os-window on your primary monitor while sending code to the shell which is in a seperate kitty-os-window on another monitor.
```

###### Zellij
```vim
let g:jukit_zellij_output_direction = 'right'
"    - Direction in which a new output pane is created relative to the vim pane. One of 'left', 'right', 'up', 'down'. Used as the `--direction` argument to `zellij action new-pane`. Ignored when `g:jukit_output_float = 1`.
let g:jukit_output_float = 0
"    - When 1, the output pane is created as a floating zellij pane (`zellij action new-pane --floating`) instead of a tiled one. Floating mode plays well with the hide/show toggle described below. Setting this to 1 on a non-zellij backend prints a warning at startup and resets it to 0.
let g:jukit_sixelcat_width_factor = 1.8
"    - Multiplier for the maximum width of inline sixel plots, expressed as a fraction of the terminal width. Increase to allow larger plots; decrease to constrain them. Applies both to live plots in the output pane (via the sixelcat matplotlib backend) and to inline saved-plot rendering via the `%jukit_out_hist` magic. Only relevant when `g:jukit_terminal = 'zellij'`.
let g:jukit_session_switch_keybind = '<leader>ss'
"    - Buffer-local mapping that opens the multi-session picker. See "Multi-session" below. Only mapped when `g:jukit_terminal = 'zellij'`. Set to '' to skip the default mapping entirely.
```

*Notes on the zellij backend:*
 * `g:jukit_layout` proportions are **not** honored on zellij — zellij has no absolute-sizing API. Pane creation respects `g:jukit_zellij_output_direction`, but the resulting proportions are whatever zellij chooses by default. Use a zellij KDL layout file if you want fully custom geometry, or the resize function below to nudge after creation.
 * Inline plotting on zellij requires both a sixel-capable terminal (e.g. foot, xterm with sixel, WezTerm) **and** `libsixel-bin` (for `img2sixel`). Until upstream zellij ships native sixel support, you may also need a patched zellij build — see `scripts/install_and_patch_zellij.sh` for the author's personal build helper. If `img2sixel` is not on `$PATH`, vim-jukit will print a warning and disable inline plotting automatically.
 * If you don't explicitly set `g:jukit_terminal`, vim-jukit will detect zellij via the `$ZELLIJ` environment variable.

*Resizing the output pane (optional keybinds):*
A helper lets you nudge the output pane size after creation. Not bound by default — add your own mapping if you want it. Takes an action (`'increase'` or `'decrease'`) and an optional step count (default 5). Each step is one zellij resize bump (~5% of the parent split).
```vim
" Optional zellij resize keybinds — add to your config if desired.
nnoremap <leader>o> :call jukit#zellij#layouts#resize_output('increase', 5)<cr>
nnoremap <leader>o< :call jukit#zellij#layouts#resize_output('decrease', 5)<cr>
```
You can also always use zellij's native resize-mode (`Ctrl+p` then `r`) as an alternative.

*Inline cell-output rendering:*
The `<leader>so` keybinding sends the IPython magic `%jukit_out_hist <cell_id>` (defined in `helpers/jukit_run/jukit_run.py`) to the output pane. The magic clears the visible screen (scrollback is preserved — scroll up to find your previous live output), prints a cell-id header, and renders the saved outputs for that cell from `.jukit/<file>_outhist.json`. Text outputs go through IPython's normal stdout; image outputs go through the existing matplotlib + sixel pipeline that's already active for live plots. Image scaling honors `g:jukit_sixelcat_width_factor` the same way the live-plot path does. **Markdown cells** currently fall through to "no saved output" — see `markdown_next_steps.md` at the repo root for the deferred markdown-rendering design.

*Multi-session (zellij only):*
On the zellij backend, each buffer carries its own list of named "sessions". A session is a labeled output (or term) pane that you can hide, show, switch between, and have multiple of in parallel within the same source file:

| Mapping | Behavior on zellij |
|---|---|
| `<leader>os` | If no session exists yet for this buffer, prompts you for a session name and creates a new session with an output pane. If the active session's output pane is currently visible, hides it. If it's hidden, shows it. (Same shape for `<leader>ts` for term mode.) |
| `<leader>ss` | Opens the session picker (a centered floating window). Lists all sessions in this buffer (sorted by most-recently-used) plus a `Create new...` entry at the bottom. Use `j`/`k`/arrows to navigate, `<CR>` to confirm, `<Esc>`/`q` to cancel. Picking an existing session swaps which session is active and reproduces the previous visibility shape. Picking `Create new...` prompts for a name (also a floating dialog) and immediately auto-spawns an output pane if the previous session had one visible. Default `<leader>ss` is configurable via `g:jukit_session_switch_keybind`. |

The hide/show mechanic uses zellij's native primitives:
 * **Floating mode** (`g:jukit_output_float = 1`): the output pane is created as a **pinned** floating pane (`new-pane --floating --pinned true`) positioned in the half-screen quadrant matching your `g:jukit_zellij_output_direction` (e.g. `right` lands in the right half). Pinning is what lets the float survive clicking back into vim. Hide / show toggles use `hide-floating-panes` / `show-floating-panes`. **Caveat**: those two commands are global to the current tab — if you have unrelated floating panes from other workflows, they get toggled too.
 * **Tiled mode** (default): zellij has no native "hide a tiled pane without closing it" action, so vim-jukit uses a `toggle-pane-embed-or-floating` round-trip. The hide flow converts the tiled pane to floating, then toggles the float layer off. The show flow reverses both steps. The pane's process keeps running with its full state intact.

The session list lives in buffer-local memory only — restarting vim resets it.

*Troubleshooting:*
 * **`<enter>` does nothing / code seems to vanish:** the most likely cause is that the output pane was closed from outside vim and `g:jukit_output_title` is stale. Run `:echo jukit#zellij#splits#exists('output')` — if it returns `0`, just `<leader>os` again to recreate the pane.
 * **No plot visible after `<leader>so`:** check that `img2sixel` is installed (`libsixel-bin`) and that your terminal speaks sixel. The same requirements apply to live plots in the output pane.
 * **Sends go to the wrong pane:** this would be a regression — the identity-based targeting in vim-jukit ≥ this commit should make it impossible. Please open an issue with the output of `:echo $ZELLIJ_PANE_ID`, `:echo g:jukit_output_title`, and `:!zellij action dump-layout | grep jukit`.
 * **Leftover jukit panes after vim quit / vim crash:** the `QuitPre`/`BufDelete` autocmd closes every pane in every session for the buffer being torn down, so a clean `:qa` should leave nothing behind. But if vim was killed externally, or you're cleaning up panes accumulated from older builds that didn't have multi-session cleanup, you can sweep them with the snippet below.

```sh
zellij action list-panes --json | python3 -c "
import json, sys
for p in json.load(sys.stdin):
    if 'jukit_' in p.get('title', ''):
        print(p['id'])
" | xargs -I {} zellij action close-pane --pane-id terminal_{}
```

###### IPython
```vim
let g:jukit_in_style = 2
"    - Number between 0 and 4. Defines how the input-code should be represented in the IPython shell. One of 5 different styles can be chosen, where style 0 is the default IPython style for the IPython-`%paste` command
let g:jukit_max_size = 20
"    - Max Size of json containing saved output in MiB. When the output history json gets too large, certain jukit operations can get slow, thus a max size is specified. Once the max size is reached, you'll be asked to delete some of the saved outputs (using e.g. jukit#cells#delete_outputs - see function explanation further down) before further output can be saved.
let g:jukit_show_prompt = 0
"    - Whether to show (1) or hide (0) the previous ipython prompt after code is sent to the ipython shell

" IF AN IPYTHON SHELL COMMAND IS USED:
let g:jukit_save_output = 1
"    - Whether to save ipython output or not. This is the default value if an ipython shell command is used.
" ELSE:
let g:jukit_save_output = 0
"    - Whether to save ipython output or not. This is the default value if ipython is not used.

let g:jukit_clean_outhist_freq = 60 * 10
"    - Frequency in seconds with which to delete obsolete entries from the on-disk `.jukit/<file>_outhist.json` data store. After executing a cell of a buffer for the first time in a session, a CursorHold autocmd is created for this buffer which checks whether the last time obsolete output got deleted was more than `g:jukit_clean_outhist_freq` seconds ago, and if so, deletes all saved output of cells which are not present in the buffer anymore.
```

###### Matplotlib
```vim
let g:jukit_savefig_dpi = 150
"    - Value for `dpi` argument for matplotlibs `savefig` function
let g:jukit_mpl_block = 1
"    - If set to 0, then `plt.show()` will by default be executed as if `plt.show(block=False)` was specified
let g:jukit_custom_backend = -1
"    - Custom matplotlib backend to use

" IF KITTY IS USED:
let g:jukit_mpl_style = jukit#util#plugin_path() . '/helpers/matplotlib-backend-kitty/backend.mplstyle'
"    - File specifying matplotlib plot options. This is the default value if kitty terminal is used
" ELSE:
let g:jukit_mpl_style = ''
"    - File specifying matplotlib plot options. This is the default value if kitty terminal is NOT used. If '' is specified, no custom mpl-style is applied.

" IF KITTY, TMUX OR ZELLIJ IS USED:
let g:jukit_inline_plotting = 1
"    - Enable in-terminal-plotting. Only supported for kitty, tmux+iTerm2, or zellij (the latter requires a sixel-capable terminal AND a zellij build with sixel patches — see the Zellij section below). BE SURE TO SPECIFY THE TERMINAL VIA `g:jukit_terminal`! (see variables in section 'Basic jukit options')
" ELSE:
let g:jukit_inline_plotting = 0
"    - Disable in-terminal-plotting
```

###### Split layout
```vim
" You can define a custom split layout as a dictionary, the default is:
let g:jukit_layout = {
    \'split': 'horizontal',
    \'p1': 0.6,
    \'val': ['file_content', 'output']
\}

" this results in the following split layout:
"  ______________________________________
" |                      |               |
" |                      |               |
" |                      |               |
" |                      |               |
" |                      |               |
" |                      |               |
" |                      |               |
" |    file_content      |     output    |
" |                      |               |
" |                      |               |
" |                      |               |
" |                      |               |
" |                      |               |
" |______________________|_______________|
"
" dictionary keys:
" 'split':  Split direction of the two splits specified in 'val'. Either 'horizontal' or 'vertical'
" 'p1':     Proportion of the first split specified in 'val'. Value must be a float with 0 < p1 < 1
" 'val':    A list of length 2 specifying the two named panes. Each entry must
"           be one of: 'file_content', 'output'.
"
" To not use any layout, specify `let g:jukit_layout=-1`
```

### Functions and Default Mappings
For function explanations see the comments below each mapping
###### Splits
```vim
nnoremap <leader>os :call jukit#splits#output()<cr>
"   - Opens a new output window and executes the command specified in `g:jukit_shell_cmd`
nnoremap <leader>ts :call jukit#splits#term()<cr>
"   - Opens a new output window without executing any command
nnoremap <leader>od :call jukit#splits#close_output_split()<cr>
"   - Close output window
nnoremap <leader>so :call jukit#splits#show_last_cell_output(1)<cr>
"   - Render the saved output of the current cell inline in the output pane via the `%jukit_out_hist <cell_id>` IPython magic. Sends the magic to the existing output pane, which clears the visible screen (scrollback preserved) and re-renders the cell's saved text and image outputs. Argument: 1 to force a re-render even if the cursor is on the same cell as the last invocation.
nnoremap <leader>j :call jukit#splits#out_hist_scroll(1)<cr>
"   - Page-scroll the output pane down. Argument: 1 = down, 0 = up.
nnoremap <leader>k :call jukit#splits#out_hist_scroll(0)<cr>
"   - Page-scroll the output pane up. Argument: 1 = down, 0 = up.
nnoremap <leader>sl :call jukit#layouts#set_layout()<cr>
"   - Apply layout (see `g:jukit_layout`) to current splits - NOTE: it is expected that this function is called from the main file buffer/split
```
###### Sending code
```vim
nnoremap <leader><space> :call jukit#send#section(0)<cr>
"   - Send code within the current cell to output split (also saves the output if ipython is used and `g:jukit_save_output==1`). Argument: if 1, will move the cursor to the next cell below after sending the code to the split, otherwise cursor position stays the same.
nnoremap <cr> :call jukit#send#line()<cr>
"   - Send current line to output split
vnoremap <cr> :<C-U>call jukit#send#selection()<cr>
"   - Send visually selected code to output split
nnoremap <leader>cc :call jukit#send#until_current_section()<cr>
"   - Execute all cells until the current cell
nnoremap <leader>all :call jukit#send#all()<cr>
"   - Execute all cells
```
###### Cells
```vim
nnoremap <leader>co :call jukit#cells#create_below(0)<cr>
"   - Create new code cell below. Argument: Whether to create code cell (0) or markdown cell (1)
nnoremap <leader>cO :call jukit#cells#create_above(0)<cr>
"   - Create new code cell above. Argument: Whether to create code cell (0) or markdown cell (1)
nnoremap <leader>ct :call jukit#cells#create_below(1)<cr>
"   - Create new textcell below. Argument: Whether to create code cell (0) or markdown cell (1)
nnoremap <leader>cT :call jukit#cells#create_above(1)<cr>
"   - Create new textcell above. Argument: Whether to create code cell (0) or markdown cell (1)
nnoremap <leader>cd :call jukit#cells#delete()<cr>
"   - Delete current cell
nnoremap <leader>cs :call jukit#cells#split()<cr>
"   - Split current cell (saved output will then be assigned to the resulting cell above)
nnoremap <leader>cM :call jukit#cells#merge_above()<cr>
"   - Merge current cell with the cell above
nnoremap <leader>cm :call jukit#cells#merge_below()<cr>
"   - Merge current cell with the cell below
nnoremap <leader>ck :call jukit#cells#move_up()<cr>
"   - Move current cell up
nnoremap <leader>cj :call jukit#cells#move_down()<cr>
"   - Move current cell down
nnoremap <leader>J :call jukit#cells#jump_to_next_cell()<cr>
"   - Jump to the next cell below
nnoremap <leader>K :call jukit#cells#jump_to_previous_cell()<cr>
"   - Jump to the previous cell above
nnoremap <leader>ddo :call jukit#cells#delete_outputs(0)<cr>
"   - Delete saved output of current cell. Argument: Whether to delete all saved outputs (1) or only saved output of current cell (0)
nnoremap <leader>dda :call jukit#cells#delete_outputs(1)<cr>
"   - Delete saved outputs of all cells. Argument: Whether to delete all saved outputs (1) or only saved output of current cell (0)
```
###### ipynb conversion
```vim
nnoremap <leader>np :call jukit#convert#notebook_convert("jupyter-notebook")<cr>
"   - Convert from ipynb to py or vice versa. Argument: Optional. If an argument is specified, then its value is used to open the resulting ipynb file after converting script.
nnoremap <leader>ht :call jukit#convert#save_nb_to_file(0,1,'html')<cr>
"   - Convert file to html (including all saved outputs) and open it using the command specified in `g:jukit_html_viewer'. If `g:jukit_html_viewer` is not defined, then will default to `g:jukit_html_viewer='xdg-open'`. Arguments: 1.: Whether to rerun all cells when converting 2.: Whether to open it after converting 3.: filetype to convert to 
nnoremap <leader>rht :call jukit#convert#save_nb_to_file(1,1,'html')<cr>
"   - same as above, but will (re-)run all cells when converting to html
nnoremap <leader>pd :call jukit#convert#save_nb_to_file(0,1,'pdf')<cr>
"   - Convert file to pdf (including all saved outputs) and open it using the command specified in `g:jukit_pdf_viewer'. If `g:jukit_pdf_viewer` is not defined, then will default to `g:jukit_pdf_viewer='xdg-open'`. Arguments: 1.: Whether to rerun all cells when converting 2.: Whether to open it after converting 3.: filetype to convert to. NOTE: If the function doesn't work there may be issues with your nbconvert or latex version - to debug, try converting to pdf using `jupyter nbconvert --to pdf --allow-errors --log-level='ERROR' --HTMLExporter.theme=dark </abs/path/to/ipynb> && xdg-open </abs/path/to/pdf>` in your terminal and check the output for possible issues.
nnoremap <leader>rpd :call jukit#convert#save_nb_to_file(1,1,'pdf')<cr>
"   - same as above, but will (re-)run all cells when converting to pdf. NOTE: If the function doesn't work there may be issues with your nbconvert or latex version - to debug, try converting to pdf using `jupyter nbconvert --to pdf --allow-errors --log-level='ERROR' --HTMLExporter.theme=dark </abs/path/to/ipynb> && xdg-open </abs/path/to/pdf>` in your terminal and check the output for possible issues.
```

*NOTE*: in case you're using the snap version of firefox to display ipynb notebooks, see [this issue](https://github.com/luk400/vim-jukit/issues/52).

### Commands

```
:JukitOut some command to be run before opening shell
```

When working in a virtual environment, you can activate it before running the shell command using the `JukitOut` command, for example:

```vim
:JukitOut conda activate MyCondaEnv
```

This will open a new output split, activate the virtual conda-environment, and then start the output shell as usual.

### Creating your own convenience functions

Using `jukit#send#send_to_split`, you can create mappings for commands you often use in your programming workflow. Here are a few examples which I personally use regularly:

* Example 1: When working with pandas in python, I often find myself typing `df.columns` to print out the columns of the dataframe in the shell. The following makes it so I can simply visually select the variable `df`, press `C`, and `df.columns` will be sent to the output split.
```vim
fun! DFColumns()
    let visual_selection = jukit#util#get_visual_selection()
    let cmd = visual_selection . '.columns'
    call jukit#send#send_to_split(cmd)
endfun
vnoremap C :call DFColumns()<cr>
```

* Example 2: Displaying help and documentation for a given function or object. The following makes it so I can visually select an object/function and press `H` to get documentation for it. E.g.: simply visually select `df.plot` in your code, press `H` and it'll display the documentation for the plot method of the dataframe.
```vim
fun! PythonHelp()
    let visual_selection = jukit#util#get_visual_selection()
    let cmd = 'help(' . visual_selection . ')'
    call jukit#send#send_to_split(cmd)
endfun
vnoremap H :call PythonHelp()<cr>
```

* Example 3: Getting all attributes of a visually selected object which contain the specified string argument. E.g.: visually select `df` in your code, press `A`, type `"set"` (in quotes!), then press enter, and it'll display all attributes of the pandas dataframe containing "set" in their name.
```vim
fun! GetAttr(str)
    let visual_selection = jukit#util#get_visual_selection()
    let cmd = '[el for el in dir(' . visual_selection . ') if "' . a:str . '" in el.lower()]'
    call jukit#send#send_to_split(cmd)
endfun
command! -nargs=1 GetAttr :call GetAttr(<args>)
vnoremap A :<c-u>GetAttr
```

### Jupyter notebook conversion - currently supported languages

Below you'll find the currently supported languages for converting notebooks to scripts and vice versa. It's very easy to add support for most languages (should only be a single line in the ipynb_convert helper module). **If you're working with a language which is currently not listed below, please create a quick issue specifying the missing language and I'll try to add it.**

Already supported:
* python
* r
* matlab
* julia
* java
* rust
* lua

### Notes to be aware of

* vim-jukit creates a directory called `.jukit` in the directory of your relevant python script for communicating with ipython and for saving ipython outputs
* If you want to save cell outputs from ipython, you should always try using jukit functions to create/delete cell markers (i.e. use the `jukit#cells#create_...()`, `jukit#cells#delete()`, `jukit#cells#merge_...()`, `jukit#cells#split()` functions) instead of simply deleting them with e.g. `dd` or yanking and pasting them to create new ones. This is because the cell ids assigned to cells above/below of a marker (by which the saved outputs for specific cells are identified) are encoded in the line of the cell marker, and simply deleting those without correcting the cell-ids in lines of adjacent cell markers or creating duplicate cell ids by yanking and pasting them may lead to unexpected cell-id-assignments for saved outputs (even though vim-jukit tries to detect and correct such manual cell marker modifications).
* If you need to switch from sending code to the output split via the ipython magic command to directly sending the text to the output split without using magic commands (for example when debugging using pdb), you can do so by using `:let g:jukit_ipython=0`, and `:let g:jukit_ipython=1` to switch back to using jukit ipython-magic
* Converting .ipynb files currently only works for notebooks with notebook-format v4+, older notebook versions must first be converted using e.g. `jupyter nbconvert --to notebook --nbformat 4 <FILENAME>`
* if you're often working with different languages and don't always want to manually set the `g:jukit_comment_mark` variable to comment out created cell markers when switching filetypes, you can install the [tcomment plugin](https://github.com/tomtom/tcomment_vim) and specify `let g:jukit_use_tcomment = 1` in your (neo)vim config.

### Credit

vim-jukit uses a for this plugin modified version of the module [ipynb_py_convert](https://github.com/kiwi0fruit/ipynb-py-convert) as well as a modified version of [matplotlib-backend-kitty](https://github.com/jktr/matplotlib-backend-kitty), which were the starting point and the initial inspiration for this plugin. It also uses the imgcat script from [python-imgcat](https://github.com/wookayin/python-imgcat) for displaying matplotlib plots in terminal when using tmux+iterm2.
