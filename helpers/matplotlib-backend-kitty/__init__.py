# SPDX-License-Identifier: CC0-1.0

import codecs, sys, io, subprocess
from matplotlib.backend_bases import _Backend, FigureManagerBase, Gcf
from matplotlib.backends.backend_agg import FigureCanvasAgg
import matplotlib.pyplot as plt


# TODO: move kitty related functions to their own file
def build_kitty_cmd(*cmd):
    def f(*args, output=True, **kwargs):
        if output:
            kwargs["capture_output"] = True
            kwargs["text"] = True
        r = subprocess.run(cmd + args, **kwargs)
        if output:
            return r.stdout.rstrip()

    return f


icat = build_kitty_cmd("kitty", "+kitten", "icat")


def _store_img_for_ipynb(img_hex_code):
    if sys.stdout.jukit_plots_size > sys.stdout.max_plots_size:
        sys.stdout._wrapped_stdout.write(
            "\u001b[31m------------------------------------\n"
            " [vim-jukit] -- PLACEHOLDER -- PLOT NOT SAVED: MAX SIZE ("
            f"{sys.stdout.max_plots_size/2**20:.1f}MiB) REACHED\n"
            "------------------------------------\n\u001b[0m"
        )
        return

    b64 = codecs.encode(codecs.decode(img_hex_code, "hex"), "base64").decode()
    sys.stdout._wrapped_stdout.write("<-- JUKIT_PLOT_PLACEHOLDER -->\n")
    sys.stdout.add_jukit_plot(b64)


class JukitFigureManager(FigureManagerBase):
    def jukit_show(self, scaling=0.75, align="center"):
        term_width, term_height = icat("--print-window-size").split("x")
        term_width, term_height = int(term_width), int(term_height)

        dpi = self.canvas.figure.dpi
        width = min(term_width, term_height) / dpi * scaling
        x, y = self.canvas.figure.get_size_inches()
        aspect_ratio = y / x
        self.canvas.figure.set_size_inches((width, width * aspect_ratio))

        if hasattr(sys.stdout, "add_jukit_plot"):
            if "save_dpi" in plt.show.__annotations__.keys():
                dpi = plt.show.__annotations__["save_dpi"]
            else:
                dpi = 150

            with io.BytesIO() as save_buf:
                self.canvas.figure.savefig(save_buf, format="png", dpi=dpi)
                _store_img_for_ipynb(save_buf.getbuffer().hex())

        with io.BytesIO() as buf:
            self.canvas.figure.savefig(buf, format="png")
            icat("--align", align, "--silent", output=False, input=buf.getbuffer())

    def show(self, *_, **kwargs):
        scaling = kwargs.get("scaling", 0.9)
        align = kwargs.get("align", "center")
        self.jukit_show(scaling, align)
        self.canvas.setVisible(True)
        Gcf.destroy_all()


class JukitCanvas(FigureCanvasAgg):
    visible = False

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
            manager.show(scaling, align)
