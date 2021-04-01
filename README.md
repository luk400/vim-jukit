# vim-jukit

This plugin aims to provide an alternative for users who frequently work with python in jupyter-notebook and who are searching for a way to work with jupyter-notebook files in vim.

It uses the graphical capabilities of the kitty terminal (https://github.com/kovidgoyal/kitty) and incorporates the functionality of ipynb_py_convert (https://github.com/kiwi0fruit/ipynb-py-convert) and matplotlib-backend-kitty (https://github.com/jktr/matplotlib-backend-kitty) to:
- easily send code to another split-window in the kitty-terminal 
- run individual lines, visually selected code, or cells like in jupyter-notebook
- display matplotlib plots in the terminal using the python/ipython shell and matplotlib-backend-kitty
- convert jupyter-notebook files to simple python-files and back using ipynb_py_convert

### Workflow

Converting a given .ipynb file to a simple .py file:
-- example --

Opening python shell in split window and sending code
-- example --

Creating cell markers
-- example --

Converting back to .ipynb
-- example --

Converting .ipynb to html and open
-- example --

### Requirements:

* kitty terminal emulator (https://github.com/kiwi0fruit/ipynb-py-convert)
* vim with python3
* vim with '+clipboard' to access the system clipboard (check with 'echo has("clipboard")')

### Installation

With your plugin manager of choice, e.g.:

```
Plug 'luk400/vim-jukit' 
```

### Other notes:

When using ipython, be aware that the text is copied to the system clipboard and then pasted into the ipython shell using '%paste', thus modifying the contents of your system clipboard. 
To send code to the REPL, text is yanked to the 'x' register, thus the contents of @x will be overwritten.
Converting ipynb to other (non-python) files has only been tested with pdf and html thus far, and there's cases where converting to pdf fails (e.g. when image in ipynb should by displayed by link).

-----------------------------
" use the following command to execute a command in terminal before opening
" ipython. So if you want to start ipython in a virtual environment, you can
" simply use ':Ipython conda activate myvenv'

-------------------------------------
-------------------------------------
-------------------------------------
-------------------------------------
-------------------------------------
BEFORE MAKING PUBLIC - TEST EVERY FUNCTION AGAIN! ALSO VENV!
-------------------------------------
-------------------------------------
-------------------------------------
-------------------------------------
-------------------------------------
