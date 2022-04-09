import matplotlib.pyplot as plt
import codecs, io, sys


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


def show_wrapper(show):
    def _wrapped(*args, **kwargs):
        if hasattr(sys.stdout, "add_jukit_plot"):
            fignums = plt.get_fignums()
            if "save_dpi" in plt.show.__annotations__.keys():
                dpi = plt.show.__annotations__["save_dpi"]

            for num in fignums:
                fig = plt.figure(num)
                with io.BytesIO() as save_buf:
                    fig.savefig(save_buf, format="png", dpi=dpi)
                    _store_img_for_ipynb(save_buf.getbuffer().hex())
        show(*args, **kwargs)
    return _wrapped
