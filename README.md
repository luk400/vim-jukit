# vim-jukit

This plugin aims to provide an alternative for users who frequently work with jupyter-notebook and are searching for a way to work with jupyter-notebook files in vim. Many of this plugin's features are meant for python only, however if you're only intending to use the functionality of sending code and using cell-markers, then this should work with any language. The goal of this plugin is not to replicate the features of jupyter-notebook in vim, but merely to provide a convenient way to convert and edit the contents of jupyter-notebook files using vim.

It uses the graphical capabilities of the [kitty terminal emulator](https://github.com/kovidgoyal/kitty) and incorporates the functionality of the packages [ipynb_py_convert](https://github.com/kiwi0fruit/ipynb-py-convert) as well as [matplotlib-backend-kitty](https://github.com/jktr/matplotlib-backend-kitty) and makes it possible to:
* easily send code to another split-window in the kitty-terminal 
* run individual lines, visually selected code, or whole cells like in jupyter-notebook
* display matplotlib plots in the terminal using `matplotlib-backend-kitty` 
* convert jupyter-notebook files to simple python-files and back using `ipynb_py_convert`

## Examples

* Converting a .ipynb file to a .py file
![converting_to_py](https://user-images.githubusercontent.com/57172028/113441420-95396c00-93ee-11eb-8474-02f9e264bf59.gif)


* Sending visual selection, code between cell-markers, or single lines to python shell, creating cell-markers, plotting directly in the terminal
![sending_code_python](https://user-images.githubusercontent.com/57172028/113440464-c44ede00-93ec-11eb-9e75-0a7b4b1b96d0.gif)


* Sending code to IPython shell using '%paste'
![sending_code_ipython](https://user-images.githubusercontent.com/57172028/113440477-cadd5580-93ec-11eb-8a6e-0f350f07cb6c.gif)


* Converting .py file back to .ipynb, then convert to .pdf and open it
![converting_to_pdf](https://user-images.githubusercontent.com/57172028/113441436-9b2f4d00-93ee-11eb-9594-f6602a6c48a8.gif)



## Requirements

* [kitty terminal emulator](https://github.com/kovidgoyal/kitty)
* remote control needs to be enabled in kitty config (i.e. put `allow_remote_control yes` in your kitty.conf)
* ImageMagick for displaying plots in the terminal (install using `sudo apt-get install imagemagick`)
* vim with python3 support
* vim with '+clipboard' to access the system clipboard (check with `:echo has("clipboard")` in vim)

## Installation

With your plugin manager of choice, e.g. using vim-plug:

```vim
Plug 'luk400/vim-jukit' 
```

## Usage

#### User defined variables

###### Default values
```vim
let g:jukit_highlight_markers = 1
let g:jukit_hl_settings = 'ctermbg=22 ctermfg=22'
let g:jukit_use_tcomment = 0
let g:jukit_comment_mark_default = '#'
let g:jukit_python_cmd = 'python3'
let g:jukit_inline_plotting_default = 1
let g:jukit_register = 'x'
let g:jukit_html_viewer = 'firefox'
let g:jukit_pdf_viewer = 'zathura'
let g:jukit_mappings = 1
```

###### Explanation
* `g:jukit_highlight_markers`: Specify if cell markers should be highlighted (1) or not (0)

* `g:jukit_hl_settings`: Specify arguments for highlighting cell markers (see `:h highlight-args`)

* `g:jukit_comment_mark_default`: Every time a buffer is entered the variable `b:comment_mark` is set according to `g:jukit_comment_mark_default` to prepend the cell-markers in the file. Only required if `g:jukit_use_tcomment=0`.

* `g:jukit_use_tcomment`: Specify if [tcomment plugin](https://github.com/tomtom/tcomment_vim) should be used to comment out cell markers - recommended if you regularly work with different languages for which you intend to make use of cell markers, otherwise you will have to manually set `b:comment_mark` every time you work in a language where the comment-mark is not the one specified in `g:jukit_comment_mark_default`. This requires the tcomment plugin to already be installed.

* `g:jukit_python_cmd`: Specifies the terminal command to use to start the interactive python shell (e.g. 'python3' or 'ipython3')

* `g:jukit_inline_plotting_default`: Every time a buffer is entered the variable `b:inline_plotting` is set according to this value, which either enables (1) or disables (0) directly plotting into terminal using matplotlib.

* `g:jukit_jukit_register`: This is the register to which jukit will yank code when sending to the kitty-terminal-window.

* `g:jukit_html_viewer` and `g:jukit_pdf_viewer`: Specifies the html-viewer and pdf-viewer to use when using the `jukit#SaveNBToFile()` function (see next section)

* `g:jukit_mappings`: If set to 0, no jukit function mappings will be set by default.

### Functions and Mappings

###### Default mappings
```vim
nnoremap <leader>py :call jukit#PythonSplit()<cr>
nnoremap <leader>sp :call jukit#WindowSplit()<cr>
nnoremap <cr> :call jukit#SendLine()<cr>
vnoremap <cr> :<C-U>call jukit#SendSelection()<cr>
nnoremap <leader><space> :call jukit#SendSection()<cr>
nnoremap <leader>cc :call jukit#SendUntilCurrentSection()<cr>
nnoremap <leader>all :call jukit#SendAll()<cr>
nnoremap <leader>mm :call jukit#NewMarker()<cr>
nnoremap <leader>np :call jukit#NotebookConvert()<cr>
nnoremap <leader>ht :call jukit#SaveNBToFile(0,1,'html')<cr>
nnoremap <leader>rht :call jukit#SaveNBToFile(1,1,'html')<cr>
nnoremap <leader>pd :call jukit#SaveNBToFile(0,1,'pdf')<cr>
nvnoremap <leader>h :<C-U>call jukit#PythonHelp()
```

###### Explanation
* `jukit#PythonSplit()`: Creates a new kitty-terminal-window and opens the python shell using the matplotlib backend for inline plotting (if `b:inline_plotting == 1`)

* `jukit#WindowSplit()`: Opens a new kitty-terminal-window. Use this if you don't want to automatically open the python shell (e.g. if you want to work with another programming language).

* `jukit#SendLine()`: Sends the line at the current cursor position to the other window

* `jukit#SendSelection()`: Sends the visually selected text

* `jukit#SendSection()`: Sends the whole current section (i.e. the code inbetween cell-markers)

* `jukit#SendUntilCurrentSection()`: Sends from the beginning of the file until (and including) the current section

* `jukit#SendAll()`: Send content of whole file

* `jukit#NewMarker()`: Create a new cell-marker

* `jukit#NotebookConvert()`: Convert from .ipynb to .py or from .py to .ipynb depending on current file extension

* `jukit#SaveNBToFile(0,1,'html')`: Convert the existing .ipynb to .html and open it

* `jukit#SaveNBToFile(1,1,'html')`: Convert the existing .ipynb to .html and open it, but run the code and include output

* `jukit#SaveNBToFile(1,1,'pdf')` and `jukit#SaveNBToFile(0,1,'pdf')`: same as above, but with .pdf instead of .html

* `jukit#PythonHelp()`: shows documentation for visually selected python function/class in terminal

In general, the function `jukit#SaveNBToFile()` is explained as follows:

* `jukit#SaveNBToFile(run, open, to)`: Must have Jupyter installed to work, since it uses the terminal command `jupyter nbconvert`. Here, `run` should be 1 or 0 and specifies if the code should be run to include output when converting, `open` should be 1 or 0 indicating if the file should be opened afterwards, and `to` specifies the output format. Generally, `to` can take any argument accepted by the `--to` flag of `jupyter nbconvert` (see `jupyter nbconvert -h`), note however that this has only been tested with pdf and html, and you need to specify a viewer variable to then open the file (i.e. to use `jukit#SaveNBToFile(0, 1, 'pdf')` the variable `g:jukit_pdf_viewer` needs to exist).

### Commands

When working with virtual environments, you can activate it before starting the python shell using the `JukitPy` command, e.g.:


```vim
:JukitPy conda activate myvenv
```

This will open a new kitty-terminal-window, activate the virtual environment using the given command, and then open the python shell with the matplotlib backend for inline plotting (if `b:inline_plotting = 1`).

## Other notes to be aware of

* When using ipython, be aware that the code is copied to the system clipboard and then pasted into the ipython shell using '%paste', thus modifying the contents of your system clipboard. 
* Converting .ipynb-files using the `jukit#SaveNBToFile()` function has only been tested with pdf and html output thus far, and there are cases where converting to pdf may fail (e.g. when an image in the notebook should by displayed using a hyperlink).
* Every time you open the python shell using `jukit#PythonSplit()` with `b:inline_plotting=1`, matplotlib is automatically imported at the beginning (to specify the backend matplotlib should use).
* Converting .ipynb file currently only works for files with notebook format v4+, older file versions must first be converted using `jupyter-notebook`
* If you're using the python shell instead of ipython and need to indent empty lines in indented code blocks (e.g. function definitions) you may want to consider a plugin like [this very basic (and somewhat underwhelming) one](https://github.com/luk400/vim-emptyindent) which I made a while ago since I didn't find anything like it.
* vim-jukit has currently only been tested on Ubuntu 20.04 (and 20.10) using python 3.8, kitty 0.15.0, and matplotlib 3.3.2
