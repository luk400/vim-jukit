import io, json, base64, re, os, sys, math, time
from matplotlib import pyplot as plt
import matplotlib.image as mpimg
from typing import List
from IPython.core.interactiveshell import InteractiveShell


KiB = 2 ** 10
MiB = 2 ** 20


def jukit_info(text: str, color: str = "\u001b[31m"):
    print(color + "[vim-jukit] " + text + "\u001b[0m")


def catch_load_json(
    file: str, ntries_left: int = 10, time_between: float = 0.5
) -> dict:
    """in case file is trying to be loaded while it is being written to by
    another process. if it still can't be loaded after `ntries_left` then
    it is assumed that it is corrupted and replaced with empty json"""

    try:
        with open(file, "r", encoding="utf-8") as f:
            info = json.load(f)
    except json.JSONDecodeError:
        jukit_info(f"JSONDecodeError, number of tries left: {ntries_left}")
        if ntries_left > 0:
            time.sleep(time_between)
            info = catch_load_json(file, ntries_left=ntries_left - 1)
        else:
            jukit_info("JSON file not readable, replacing with empty json!")
            info = {}
            with open(file, "w+", encoding="utf-8") as f:
                json.dump(info, f)

    return info


def hide_prompt(shell: InteractiveShell):
    x, _ = os.get_terminal_size()
    sys.stdout.write("\033[A" + " " * x + "\033[A")


def _add_ws(x: int, str_: str, offset: int = 0, center: bool = True) -> str:
    if center:
        space_before = " " * math.floor((x - len(str_) - offset) / 2)
        space_after = " " * math.ceil((x - len(str_) - offset) / 2)
    else:
        space_before = ""
        space_after = " " * math.ceil(x - len(str_) - offset)

    return f"{space_before}{str_}{space_after}"


def display_cell_id(cell_id: str, term_width: int, min_frame_width: int = 25):
    if term_width < 5:
        return

    jukit_id_str = f"Cell ID: {cell_id}"
    w_frame = len(jukit_id_str) + 4

    center = term_width is not None
    if not term_width:
        term_width = w_frame

    wide_enough = term_width > min_frame_width
    if wide_enough:
        top = f'{"╭" + "─" * (w_frame-2) + "╮"}'
        print(f"\n\u001b[36m{_add_ws(term_width, top, center=center)}")

    str_ = "Last Outputs"

    if wide_enough:
        str_ = f"│{_add_ws(w_frame, str_, 2, center=True)}│"
    else:
        str_ = f"\n\u001b[36m{_add_ws(w_frame, str_, 0, center=False)}"

    print(_add_ws(term_width, str_, center=center))
    while len(jukit_id_str):
        if wide_enough:
            s = jukit_id_str[: (term_width - 4)]
            s = f"│{_add_ws(w_frame, s, 2, center=True)}│"
        else:
            s = jukit_id_str[: (term_width - 2)]
            s = f"{_add_ws(w_frame, s, 0, center=False)}\u001b[0m"
        print(_add_ws(term_width, s, center=center))
        jukit_id_str = jukit_id_str[(term_width - 4) :]

    if wide_enough:
        bottom = f'{"╰" + "─" * (w_frame-2) + "╯"}'
        print(f"{_add_ws(term_width, bottom, center=center)}\u001b[0m\n")


def display_outputs(outputs: List[dict], term: str, shell: InteractiveShell):
    try:
        for out in outputs:
            if out["output_type"] == "stream":
                print("".join(out["text"]))
            elif out["output_type"] == "display_data":
                if "image/png" in out["data"].keys():
                    data = out["data"]["image/png"]
                elif "text/html" in out["data"].keys():
                    data = out["data"]["text/html"][0]
                    data = re.findall(r"(?<=base64,)\S*(?=\")", data)[0]
                else:
                    jukit_info("Not able to get (all of) the display_data")
                    jukit_info(
                        f"Keys in output dict: {list(out['data'].keys())}"
                        ";\nSupported Keys: ['image/png', 'text/html']\n"
                    )
                    continue

                if term not in ["kitty", "tmux"]:
                    jukit_info("PLOT", color="\u001b[33m")

                im = base64.b64decode(data)
                im = mpimg.imread(io.BytesIO(im), format="png")
                plt.figure()
                plt.axes([0, 0, 1, 1])
                plt.axis("off")
                plt.imshow(im)
                if plt.get_backend() == "module://matplotlib-backend-kitty":
                    plt.show(scaling=0.75)
                else:
                    plt.show(block=False)
            elif out["output_type"] == "execute_result":
                out_prompt = f"\u001b[31mOut[\u001b[32m{out['execution_count']}\u001b[31m]: \u001b[0m"
                txt = out["data"]["text/plain"]
                is_str_multi_line = isinstance(txt, str) and len(txt.split("\n")) > 1
                is_iter_multi = not isinstance(txt, str) and len(txt) > 1
                is_iter_str_multi = (
                    not isinstance(txt, str) and len(txt[0].split("\n")) > 1
                )
                if is_str_multi_line or is_iter_multi or is_iter_str_multi:
                    out_prompt += "\n"
                print(out_prompt + "".join(out["data"]["text/plain"]))
            elif out["output_type"] == "error":
                print("".join(out["traceback"]))
            else:
                jukit_info(f"Output type `{out['output_type']}` could not be displayed")
    except KeyboardInterrupt:
        if os.name != "nt":
            shell.run_line_magic("clear", "")
    except BufferError:
        if os.name != "nt":
            shell.run_line_magic("clear", "")


def check_output_size(captured_out: str, outhist_file: str, max_bytes: int) -> str:
    if len(sys.stdout.jukit_plots):
        plots_size = sys.stdout.jukit_plots_size
    else:
        plots_size = 0

    out_text_size = sys.getsizeof(captured_out)
    out_size = out_text_size + plots_size
    ipynb_size = (
        0 if not os.path.isfile(outhist_file) else os.path.getsize(outhist_file)
    )
    out_size = out_text_size + plots_size

    if ipynb_size > max_bytes and out_size > 10 * KiB:
        jukit_info(
            f"Output not saved! Size of '{outhist_file}' already over max size of "
            f"{max_bytes/MiB:.1f}MiB! (currently {ipynb_size/MiB:.1f}MiB)\nOutputs requiring "
            "more than 10KiB will not be saved. Delete or increase max size. "
            "Large max size may lead to performance issues!"
        )
        return "\u001b[31m\n[vim-jukit] Output not saved (output-json was over max size)\n\u001b[0m"

    elif ipynb_size + out_size > max_bytes and out_size > 10 * KiB:
        jukit_info(
            f"Size of '{outhist_file}' has surpassed "
            f"max size of {max_bytes/MiB:.1f}MiB! (now at {(ipynb_size+out_size)/MiB:.1f}MiB)\n"
            "Any further outputs requiring "
            "more than 10KiB will not be saved. Delete large cell "
            "outputs to reduce file size or increase max size."
            "Large max size output history may lead to performance issues!"
        )

    return captured_out
