from matplotlib.backend_bases import Gcf
import matplotlib.pyplot as plt
import codecs, io, sys
import functools


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


def show_wrapper(show, mpl_block=True):
    @functools.wraps(show)
    def _wrapped(*args, **kwargs):
        if "block" not in kwargs:
            kwargs["block"] = mpl_block

        if hasattr(sys.stdout, "add_jukit_plot"):
            fignums = plt.get_fignums()
            if "save_dpi" in plt.show.__annotations__.keys():
                dpi = plt.show.__annotations__["save_dpi"]
            else:
                dpi = 150

            for num in fignums:
                fig = plt.figure(num)
                if fig.stale or kwargs["block"]:
                    with io.BytesIO() as save_buf:
                        fig.savefig(save_buf, format="png", dpi=dpi)
                        _store_img_for_ipynb(save_buf.getbuffer().hex())
        show(*args, **kwargs)

        if not kwargs["block"]:
            manager = Gcf.get_active()
            if manager is not None:
                canvas = manager.canvas
                if canvas.figure.stale:
                    canvas.draw_idle()
                canvas.start_event_loop(1e-3)

    return _wrapped
