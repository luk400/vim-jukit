This plugin uses the graphical capabilities of the kitty terminal (https://github.com/kovidgoyal/kitty) and incorporates the functionality of ipynb_py_convert (https://github.com/kiwi0fruit/ipynb-py-convert) and matplotlib-backend-kitty (https://github.com/jktr/matplotlib-backend-kitty) and makes it possible to:
- easily send code to another split-window in the kitty-terminal 
- display matplotlib plots in the terminal using the python/ipython shell
- convert jupyter-notebook files to simple python-files and back
- run individual lines, visually selected code, or cells like in jupyter-notebook

Requirements:
---
vim with python3
vim with '+clipboard' to access the system clipboard (check with 'echo has("clipboard")')

Other notes:
---
When using ipython, be aware that the text is copied to the system clipboard and then pasted into the ipython shell using '%paste', thus modifying the contents of your system clipboard. 
To send code to the REPL, text is yanked to the 'x' register, thus the contents of @x will be overwritten.
Converting ipynb to other (non-python) files has only been tested with pdf and html thus far, and there's cases where converting to pdf fails (e.g. when image in ipynb should by displayed by link).

