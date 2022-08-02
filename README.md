# vim-jukit
## REPL plugin and Jupyter-Notebook alternative for Vim and Neovim

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

* **Preview file as pdf, html**

![convert_to_html_pdf_new](https://user-images.githubusercontent.com/57172028/162511885-03675901-c701-4c9e-be41-bb68ef8a2707.gif)

* **For kitty-terminal users: optionally open splits in seperate os-windows** (useful if you have multiple monitors)

![seperate_os_window_new](https://user-images.githubusercontent.com/57172028/162546384-3e4ba886-a6ac-47a3-96e4-5033fd3f8308.gif)

* **For kitty-terminal users (and for iTerm2+tmux users): in-terminal plotting via matplotlib**

![inline_plotting_new](https://user-images.githubusercontent.com/57172028/162511949-7c521780-a6fb-4a57-b889-7b1e47f5edff.gif)


### Requirements

* vim users: version >= 8.2
* neovim users: version >= 0.4
* vim/neovim must have python3 support (check using `:echo has('python3')`)
* (i)python users:
    - ipython version >= 7.3.0
    - matplotlib version >= 3.2.0
* [kitty](https://sw.kovidgoyal.net/kitty/overview/) terminal users: 
    - kitty version >= 0.22
    - remote control needs to be enabled in kitty config (i.e. put `allow_remote_control yes` in your kitty.conf), or alternatively you can also always start kitty using `kitty -o allow_remote_control=yes`
    - ImageMagick for displaying plots in the terminal must be installed (install using e.g. `sudo apt-get install imagemagick`)
    - If you're using neovim with kitty, you need to launch kitty with the ``--listen-on`` option and specify an address to listen on ([more information](https://sw.kovidgoyal.net/kitty/invocation.html)). Furthermore, if you want to have different kitty instances simultaneously using this plugin and sending code to split windows, different addresses will need to be specified. One possible way to do this on linux machines is by simply always starting kitty with e.g. `kitty --listen-on=unix:@"$(date +%s%N)"`, which will make sure different kitty instances are launched with different, abstract sockets to listen on. On MacOS it should work using e.g. `kitty --listen-on=/tmp/kitty_"$(date +%s%N)"`. If you want, you can then simply specify an alias (i.e. put `alias jukit_kitty="kitty --listen-on=unix:@"$(date +%s%N)" -o allow_remote_control=yes"` in your .bashrc/.zshrc) which you can use to always start kitty with the necessary arguments.
* iTerm2+tmux (experimental):
    - currently only tested using iTerm2 Build 3.4.15 + tmux version 3.2a
    - There's a good chance it won't work with a different tmux version. To install the exact version it was tested with, use the following commands:
        ```
        wget https://raw.githubusercontent.com/Homebrew/homebrew-core/e44425df5a8b3c8c24073486fa7e355f3ac19657/Formula/tmux.rb
        brew install ./tmux.rb
        tmux -V # make sure it says tmux 3.2a
        brew pin tmux # prevent unintentional upgrade in the future
        ```
* windows users:
    - make sure `python3` - and not just `python` - is a valid command in your terminal, if it's not then set `let g:_jukit_python_os_cmd = 'python'` in your vim config
    - This plugin has not been extensively tested on windows and some features may not work yet. If you encounter any problems, please open an issue and I'll try my best to fix it
* to use the `jukit#convert#save_nb_to_file()` function (see function mappings below), make sure `jupyter` is installed in your environment.


### Installation

With your plugin manager of choice, e.g. using vim-plug:

```vim
Plug 'luk400/vim-jukit' 
```

## Usage

### Basic usage in a nutshell (assuming default mappings)

* **Example using ipython:**

If you have an ipynb file containing python code which you first need to convert, simply open it and press `<leader>np`. This will also preseve saved outputs.

In your python file, press `<leader>os` to start an output split.
Now you can start sending code to the shell. Simply press `<enter>` to send the line of the current cursor position to the shell. Visually select code and press `<enter>` to send it to the shell. Press `<leader><space>` to send the code in the current cell to the shell. Only output of cell executions will be saved, ipython outputs from sending single lines or visual selections will not be saved. 

Create a new cell below by pressing `<leader>co`, or `<leader>cO` to create one above. If you want to create a text/markdown cell below, use `<leader>ct`, or `<leader>cT` to create one above. You can also move cells up or down, split cells, or merge cells (see the mappings and explanations below).

Now say you've been coding for a while and want to know what the output of a specific cell was. Instead of searching for it by scrolling up in your shell or completely re-running it (which is often inconvenient for long-running code), you can press `<leader>hs` which will create a new split window where saved outputs will be displayed. Press `<leader>so` to display saved output of the current cell. To scroll up or down in the output-history-split, simply press `<leader>j` or `<leader>k`. If you don't need the output-history split anymore, simply press `<leader>hd` to close it again. 

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
For variable explanations see the comments underneath each variable
###### Basic jukit options
```vim
let g:jukit_shell_cmd = 'ipython3'
"    - Specifies the command used to start a shell in the output split. Can also be an absolute path. Can also be any other shell command, e.g. `R`, `julia`, etc. (note that output saving is only possible for ipython)
let g:jukit_terminal = ''
"   - Terminal to use. Can be one of '', 'kitty', 'vimterm', 'nvimterm' or 'tmux'. If '' is given then will try to detect terminal
let g:jukit_auto_output_hist = 0
"   - If set to 1, will create an autocmd with event `CursorHold` to show saved ipython output of current cell in output-history split. Might slow down (n)vim significantly, you can use `set updatetime=<number of milliseconds>` to control the time to wait until CursorHold events are triggered, which might improve performance if set to a higher number (e.g. `set updatetime=1000`).
let g:jukit_use_tcomment = 0
"   - Whether to use tcomment plugin (https://github.com/tomtom/tcomment_vim) to comment out cell markers. If not, then cell markers will simply be prepended with `g:jukit_comment_mark`
let g:jukit_comment_mark = '#'
"   - See description of `g:jukit_use_tcomment` above
let g:jukit_mappings = 1
"   - If set to 0, none of the default function mappings (as specified further down) will be applied
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
"    - String or list of strings specifying extensions for which the relevant highlighting autocmds regarding marker-highlighting, textcell-highlighting, etc. will be created. For example, `let g:jukit_hl_extensions=['py', 'R']` will enable the defined highlighting options for `.py` and `.R` files. Use `let g:jukit_hl_extensions=*` to enable them for all files and `let g:jukit_hl_extensions=''` to disable them completely
```

###### Kitty
```vim
let g:jukit_output_bg_color = get(g:, 'jukit_output_bg_color', '')
"    - Optional custom background color of output split window (i.e. target window of sent code)
let g:jukit_output_fg_color = get(g:, 'jukit_output_fg_color', '')
"    - Optional custom foreground color of output split window (i.e. target window of sent code)
let g:jukit_outhist_bg_color = get(g:, 'jukit_outhist_bg_color', '#090b1a')
"    - Optional custom background color of output-history window
let g:jukit_outhist_fg_color = get(g:, 'jukit_outhist_fg_color', 'gray')
"    - Optional custom foreground color of output-history window
let g:jukit_output_new_os_window = 0
"    - If set to 1, opens output split in new os-window. Can be used to e.g. write code in one kitty-os-window on your primary monitor while sending code to the shell which is in a seperate kitty-os-window on another monitor.
let g:jukit_outhist_new_os_window = 0
"    - Same as `g:jukit_output_new_os_window`, only for output-history-split
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
"    - Frequency in seconds with which to delete saved ipython output of cells which are not present anymore. (After executing a cell of a buffer for the first time in a session, a CursorHold autocmd is created for this buffer which checks whether the last time obsolete output got deleted was more than `g:jukit_clean_outhist_freq` seconds ago, and if so, deletes all saved output of cells which are not present in the buffer anymore from the output-history-json)
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

" IF KITTY OR TMUX IS USED:
let g:jukit_inline_plotting = 1
"    - Enable in-terminal-plotting. Only supported for kitty terminal or tmux with iTerm2 terminal
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
    \'val': [
        \'file_content',
        \{
            \'split': 'vertical',
            \'p1': 0.6,
            \'val': ['output', 'output_history']
        \}
    \]
\}

" this results in the following split layout:
"  ______________________________________
" |                      |               |
" |                      |               |
" |                      |               |
" |                      |               |
" |                      |     output    |
" |                      |               |
" |                      |               |
" |    file_content      |               |
" |                      |_______________|
" |                      |               |
" |                      |               |
" |                      | output_history|
" |                      |               |
" |                      |               |
" |______________________|_______________|
"
" The positions of all 3 split windows must be defined in the dictionary, even if 
" you don't plan on using the output_history split.
"
" dictionary keys:
" 'split':  Split direction of the two splits specified in 'val'. Either 'horizontal' or 'vertical'
" 'p1':     Proportion of the first split specified in 'val'. Value must be a float with 0 < p1 < 1
" 'val':    A list of length 2 which specifies the two splits for which to apply the above two options.
"           One of the two items in the list must be a string and one must be a dictionary in case of
"           the 'outer' dictionary, while the two items in the list must both be strings in case of
"           the 'inner' dictionary.
"           The 3 strings must be different and can be one of: 'file_content', 'output', 'output_history'
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
nnoremap <leader>hs :call jukit#splits#history()<cr>
"   - Opens a new output-history window, where saved ipython outputs are displayed
nnoremap <leader>ohs :call jukit#splits#output_and_history()<cr>
"   - Shortcut for opening output terminal and output-history
nnoremap <leader>hd :call jukit#splits#close_history()<cr>
"   - Close output-history window
nnoremap <leader>od :call jukit#splits#close_output_split()<cr>
"   - Close output window
nnoremap <leader>ohd :call jukit#splits#close_output_and_history(1)<cr>
"   - Close both windows. Argument: Whether or not to ask you to confirm before closing.
nnoremap <leader>so :call jukit#splits#show_last_cell_output(1)<cr>
"   - Show output of current cell (determined by current cursor position) in output-history window. Argument: Whether or not to reload outputs if cell id of outputs to display is the same as the last cell id for which outputs were displayed
nnoremap <leader>j :call jukit#splits#out_hist_scroll(1)<cr>
"   - Scroll down in output-history window. Argument: whether to scroll down (1) or up (0)
nnoremap <leader>k :call jukit#splits#out_hist_scroll(0)<cr>
"   - Scroll up in output-history window. Argument: whether to scroll down (1) or up (0)
nnoremap <leader>ah :call jukit#splits#toggle_auto_hist()<cr>
"   - Create/delete autocmd for displaying saved output on CursorHold. Also, see explanation for `g:jukit_auto_output_hist`
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
nnoremap <leader>do :call jukit#cells#delete_outputs(0)<cr>
"   - Delete saved output of current cell. Argument: Whether to delete all saved outputs (1) or only saved output of current cell (0)
nnoremap <leader>dao :call jukit#cells#delete_outputs(1)<cr>
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
"   - Convert file to pdf (including all saved outputs) and open it using the command specified in `g:jukit_pdf_viewer'. If `g:jukit_pdf_viewer` is not defined, then will default to `g:jukit_pdf_viewer='xdg-open'`. Arguments: 1.: Whether to rerun all cells when converting 2.: Whether to open it after converting 3.: filetype to convert to
nnoremap <leader>rpd :call jukit#convert#save_nb_to_file(1,1,'pdf')<cr>
"   - same as above, but will (re-)run all cells when converting to pdf
```

### Commands

```
:JukitOut some command to be run before opening shell
:JukitOutHist some command to be run before opening shell
```

When working in a virtual environment, you can activate it before running the shell command using the `JukitOut` or `JukitOutHist` command, for example:

```vim
:JukitOut conda activate MyCondaEnv
```

This will open a new output split, activate the virtual conda-environment, and then start the output shell as usual. `JukitOutHist` does the same thing but will additionally open an output-history window.

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
