import io
import sys

from matplotlib._pylab_helpers import Gcf
from matplotlib.figure import Figure
from matplotlib.backend_bases import FigureManagerBase
from matplotlib.backends.backend_agg import FigureCanvasAgg as FigureCanvas
import matplotlib.pyplot as plt

from .sixelcat import sixelcat


__version__ = '0.1.0'


def _store_img_for_ipynb(img_hex_code):
    """Store image for Jupyter notebook compatibility (jukit)."""
    if not hasattr(sys.stdout, 'add_jukit_plot'):
        return

    import codecs

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


class FigureManagerSixel(FigureManagerBase):
    """Figure manager that displays figures using sixel graphics."""

    def show(self):
        if hasattr(sys.stdout, "add_jukit_plot"):
            if "save_dpi" in plt.show.__annotations__.keys():
                dpi = plt.show.__annotations__["save_dpi"]
            else:
                dpi = 150

            with io.BytesIO() as save_buf:
                self.canvas.figure.savefig(save_buf, format="png", dpi=dpi)
                _store_img_for_ipynb(save_buf.getbuffer().hex())

        kwargs = {}

        if "sixel_width" in plt.show.__annotations__:
            kwargs['width'] = plt.show.__annotations__["sixel_width"]

        if "sixel_height" in plt.show.__annotations__:
            kwargs['height'] = plt.show.__annotations__["sixel_height"]

        if "sixel_rows" in plt.show.__annotations__:
            kwargs['rows'] = plt.show.__annotations__["sixel_rows"]

        if "use_passthrough" in plt.show.__annotations__:
            kwargs['use_passthrough'] = plt.show.__annotations__["use_passthrough"]

        if "switch_pane" in plt.show.__annotations__:
            kwargs['switch_pane'] = plt.show.__annotations__["switch_pane"]

        sixelcat(self.canvas.figure, **kwargs)


def show(block=None):
    """Display all open figures using sixel graphics."""
    for manager in Gcf.get_all_fig_managers():
        manager.show()
        Gcf.destroy(manager)


def new_figure_manager(num, *args, **kwargs):
    """Create a new figure manager instance."""
    FigureClass = kwargs.pop('FigureClass', Figure)
    fig = FigureClass(*args, **kwargs)
    return new_figure_manager_given_figure(num, fig)


def new_figure_manager_given_figure(num, figure):
    """Create a new figure manager instance for the given figure."""
    canvas = FigureCanvas(figure)
    manager = FigureManagerSixel(canvas, num)
    return manager

