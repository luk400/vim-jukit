# SPDX-License-Identifier: CC0-1.0

import base64
import io
import math
import os
import secrets
import shutil
import subprocess
import sys
import tempfile

from matplotlib.backend_bases import _Backend, FigureCanvasBase, FigureManagerBase, Gcf
import matplotlib.pyplot as plt


# First 64 entries from kitty's stable rowcolumn-diacritics.txt table. Jukit
# only needs row diacritics because columns can inherit left-to-right. This
# keeps placeholders compact while still allowing full terminal-width plots.
_ROW_DIACRITICS = tuple(
    chr(int(cp, 16))
    for cp in (
        "0305 030D 030E 0310 0312 033D 033E 033F 0346 034A 034B 034C 0350 0351 0352 0357 "
        "035B 0363 0364 0365 0366 0367 0368 0369 036A 036B 036C 036D 036E 036F 0483 0484 "
        "0485 0486 0487 0592 0593 0594 0595 0597 0598 0599 059C 059D 059E 059F 05A0 05A1 "
        "05A8 05A9 05AB 05AC 05AF 05C4 0610 0611 0612 0613 0614 0615 0616 0617 0657 0658"
    ).split()
)
_PLACEHOLDER = "\U0010EEEE"


def _store_img_for_ipynb(png_bytes):
    if sys.stdout.jukit_plots_size > sys.stdout.max_plots_size:
        sys.stdout._wrapped_stdout.write(
            "\u001b[31m------------------------------------\n"
            " [vim-jukit] -- PLACEHOLDER -- PLOT NOT SAVED: MAX SIZE ("
            f"{sys.stdout.max_plots_size/2**20:.1f}MiB) REACHED\n"
            "------------------------------------\n\u001b[0m"
        )
        return
    b64 = base64.b64encode(png_bytes).decode("ascii")
    sys.stdout._wrapped_stdout.write("<-- JUKIT_PLOT_PLACEHOLDER -->\n")
    sys.stdout.add_jukit_plot(b64)


def _real_stdout():
    # Jukit captures normal stdout in StringIOWrapper. Graphics placeholder
    # text must reach the PTY but must not become part of captured cell text.
    return getattr(sys.stdout, "_sys_stdout", sys.stdout)


def _new_image_id():
    # Unicode placeholders can carry 24 bits through truecolor foreground.
    # Keep IDs non-zero. Random IDs minimize collisions in the terminal-wide
    # image namespace without requiring terminal replies.
    return secrets.randbelow(0xFFFFFF) + 1


def _grid_size(figure, scaling, cell_aspect):
    term_cols, term_rows = shutil.get_terminal_size((80, 24))
    term_cols = max(1, term_cols)
    term_rows = max(1, term_rows)
    cell_aspect = max(float(cell_aspect), 0.1)
    scaling = max(min(float(scaling), 1.0), 0.05)

    width_in, height_in = figure.get_size_inches()
    fig_aspect = (height_in / width_in) if width_in else 1.0

    # Approximate kitty icat's pixel-size behavior without querying a Kitty
    # process. One text cell is treated as cell_aspect times taller than wide.
    max_width_cells = min(term_cols, term_rows * cell_aspect)
    cols = max(1, min(term_cols, int(math.floor(max_width_cells * scaling))))
    rows = max(1, int(math.ceil(cols * fig_aspect / cell_aspect)))

    max_rows = min(term_rows, len(_ROW_DIACRITICS))
    if rows > max_rows:
        rows = max_rows
        cols = max(1, min(term_cols, int(math.floor(rows * cell_aspect / fig_aspect))))

    return cols, rows, term_cols


def _upload_to_parent_nvim(png_bytes, image_id, cols, rows):
    server = os.environ.get("NVIM")
    if not server:
        raise RuntimeError(
            "vim-jukit Kitty-protocol graphics must run inside a Neovim :terminal"
        )

    nvim = shutil.which("nvim")
    if not nvim:
        raise RuntimeError("nvim executable not found in PATH")

    path = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix="jukit-tty-graphics-", suffix=".png", delete=False
        ) as tmp:
            tmp.write(png_bytes)
            path = tmp.name

        # NamedTemporaryFile paths contain no Vimscript-significant characters
        # on normal POSIX/Windows temp directories. fnameescape() is not useful
        # here because the value is an expression string, not an Ex argument.
        path_expr = path.replace("\\", "\\\\").replace('"', '\\"')
        expr = (
            'jukit#graphics#kitty_upload("'
            + path_expr
            + f'", {int(image_id)}, {int(cols)}, {int(rows)})'
        )
        proc = subprocess.run(
            [nvim, "--server", server, "--remote-expr", expr],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout).strip()
            raise RuntimeError(
                "failed to send Kitty graphics data through parent Neovim"
                + (f": {detail}" if detail else "")
            )
    finally:
        if path:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def _write_placeholders(image_id, cols, rows, term_cols, align):
    red = (image_id >> 16) & 0xFF
    green = (image_id >> 8) & 0xFF
    blue = image_id & 0xFF
    foreground = f"\x1b[38;2;{red};{green};{blue}m"

    if align == "right":
        padding = max(0, term_cols - cols)
    elif align == "left":
        padding = 0
    else:
        padding = max(0, (term_cols - cols) // 2)

    out = _real_stdout()
    prefix = " " * padding
    for row in range(rows):
        # Kitty protocol inheritance: with the row diacritic on the first cell,
        # following placeholder cells inherit the row and increment columns.
        line = prefix + _PLACEHOLDER + _ROW_DIACRITICS[row]
        if cols > 1:
            line += _PLACEHOLDER * (cols - 1)
        out.write("\r" + foreground + line + "\x1b[39m\r\n")
    out.flush()


class JukitFigureManager(FigureManagerBase):
    def jukit_show(self, scaling=0.75, align="center"):
        save_dpi = plt.show.__annotations__.get("save_dpi", 150)
        cell_aspect = plt.show.__annotations__.get("cell_aspect", 2.0)
        cols, rows, term_cols = _grid_size(self.canvas.figure, scaling, cell_aspect)

        with io.BytesIO() as buf:
            self.canvas.figure.savefig(buf, format="png")
            png_bytes = buf.getvalue()

        if hasattr(sys.stdout, "add_jukit_plot"):
            with io.BytesIO() as save_buf:
                self.canvas.figure.savefig(save_buf, format="png", dpi=save_dpi)
                _store_img_for_ipynb(save_buf.getvalue())

        image_id = _new_image_id()
        _upload_to_parent_nvim(png_bytes, image_id, cols, rows)
        _write_placeholders(image_id, cols, rows, term_cols, align)

    def show(self, *_, **kwargs):
        scaling = kwargs.get("scaling", 0.9)
        align = kwargs.get("align", "center")
        self.jukit_show(scaling, align)
        self.canvas.setVisible(True)
        Gcf.destroy_all()


class JukitCanvas(FigureCanvasBase):
    visible = False
    manager_class = JukitFigureManager

    def isVisible(self):
        return self.visible

    def setVisible(self, visible):
        self.visible = visible


@_Backend.export
class JukitBackend(_Backend):
    FigureCanvas = JukitCanvas
    FigureManager = JukitFigureManager
    mainloop = lambda: None

    @classmethod
    def show(cls, *_, **kwargs):
        managers = Gcf.get_all_fig_managers()
        if not managers:
            return
        for manager in managers:
            scaling = kwargs.get("scaling", 0.9)
            align = kwargs.get("align", "center")
            manager.show(scaling=scaling, align=align)
