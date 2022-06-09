import codecs, io, sys
from matplotlib._pylab_helpers import Gcf
from matplotlib.figure import Figure
from matplotlib.backend_bases import FigureManagerBase
import matplotlib.pyplot as plt

from .imgcat import imgcat


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


class FigureManagerImgcat(FigureManagerBase):
    def show(self):
        if hasattr(sys.stdout, "add_jukit_plot"):
            if "save_dpi" in plt.show.__annotations__.keys():
                dpi = plt.show.__annotations__["save_dpi"]
            else:
                dpi = 150

            with io.BytesIO() as save_buf:
                self.canvas.figure.savefig(save_buf, format="png", dpi=dpi)
                _store_img_for_ipynb(save_buf.getbuffer().hex())

        if "tmux_panes" in plt.show.__annotations__.keys():
            imgcat(self.canvas.figure, panes=plt.show.__annotations__["tmux_panes"])
        else:
            imgcat(self.canvas.figure)


def show(block=None):
    for manager in Gcf.get_all_fig_managers():
        manager.show()

        # Do not re-display what is already shown.
        Gcf.destroy(manager.num)


def new_figure_manager(num, *args, **kwargs):
    FigureClass = kwargs.pop('FigureClass', Figure)
    fig = FigureClass(*args, **kwargs)
    return new_figure_manager_given_figure(num, fig)


def new_figure_manager_given_figure(num, figure):
    # this must be lazy-loaded to avoid unwanted configuration of mpl backend
    from matplotlib.backends.backend_agg import FigureCanvasAgg

    canvas = FigureCanvasAgg(figure)
    manager = FigureManagerImgcat(canvas, num)
    return manager
