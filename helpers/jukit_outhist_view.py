#!/usr/bin/env python3
"""
Lightweight outhist viewer for vim-jukit, zellij + sixel only.

Replaces the old IPython-as-renderer outhist pane with a thin script that
reads commands from stdin and renders cells from a saved-output JSON file
directly to its own stdout. No matplotlib import, no IPython, no jupyter.

Protocol (one command per line, terminated by newline):

  cell <id>          render cell <id> from the current outhist file
  cell <id> md       render a [markdown cell] placeholder for cell <id>
  file <path>        switch the current outhist file to <path>
  clear              clear the screen
  quit               exit cleanly

Image rendering: PNG bytes are piped through ``img2sixel`` (libsixel-bin)
and the resulting sixel sequence is written directly to stdout. Image
size is constrained to the terminal viewport with the same scaling math
as the live-plot path in helpers/sixelcat/cat.py.

Markdown rendering: TODO. Currently prints "[markdown cell]" placeholder.

text/html outputs: only embedded base64 images are extracted (matching
the legacy behavior). Other HTML content like tables/formatted text is
dropped. TODO: render that too.
"""

import argparse
import base64
import json
import math
import os
import re
import struct
import subprocess
import sys
import time


# ---------------------------------------------------------------------------
# JSON loading with retry on mid-write race.
# Mirrors helpers/jukit_run/util.py:catch_load_json but iterative and
# non-destructive (returns {} on persistent failure instead of overwriting).
# ---------------------------------------------------------------------------

def load_outhist(path, max_tries=10, delay=0.5):
    """Load an outhist json file, retrying briefly on mid-write JSONDecodeError.
    Returns the parsed dict on success, {} on missing file or persistent
    decode failure."""
    if not os.path.isfile(path):
        return {}
    for tries_left in range(max_tries, 0, -1):
        try:
            with open(path, "r") as f:
                return json.load(f)
        except json.JSONDecodeError:
            jukit_info(
                f"JSONDecodeError reading {path}, "
                f"{tries_left - 1} retries left",
                color="\u001b[33m",
            )
            time.sleep(delay)
        except OSError as e:
            jukit_info(f"could not read {path}: {e}", color="\u001b[31m")
            return {}
    jukit_info(f"giving up reading {path}", color="\u001b[31m")
    return {}


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

def jukit_info(text, color="\u001b[31m"):
    print(f"{color}[vim-jukit] {text}\u001b[0m", flush=True)


def clear_screen():
    sys.stdout.write("\033[2J\033[H")
    sys.stdout.flush()


# ---------------------------------------------------------------------------
# Cell header (ported from helpers/jukit_run/util.py:display_cell_id and
# its _add_ws helper). Draws a unicode box around the cell id at the top of
# each cell render.
# ---------------------------------------------------------------------------

def _add_ws(x, s, offset=0, center=True):
    if center:
        before = " " * math.floor((x - len(s) - offset) / 2)
        after = " " * math.ceil((x - len(s) - offset) / 2)
    else:
        before = ""
        after = " " * math.ceil(x - len(s) - offset)
    return f"{before}{s}{after}"


def print_cell_header(cell_id, term_width, min_frame_width=25):
    if term_width < 5:
        return

    jukit_id_str = f"Cell ID: {cell_id}"
    w_frame = len(jukit_id_str) + 4

    wide_enough = term_width > min_frame_width
    if wide_enough:
        top = "╭" + "─" * (w_frame - 2) + "╮"
        print(f"\n\u001b[36m{_add_ws(term_width, top, center=True)}")

    label = "Last Outputs"
    if wide_enough:
        label = f"│{_add_ws(w_frame, label, 2, center=True)}│"
    else:
        label = f"\n\u001b[36m{_add_ws(w_frame, label, 0, center=False)}"

    print(_add_ws(term_width, label, center=True))
    while len(jukit_id_str):
        if wide_enough:
            piece = jukit_id_str[: (term_width - 4)]
            piece = f"│{_add_ws(w_frame, piece, 2, center=True)}│"
        else:
            piece = jukit_id_str[: (term_width - 2)]
            piece = f"{_add_ws(w_frame, piece, 0, center=False)}\u001b[0m"
        print(_add_ws(term_width, piece, center=True))
        jukit_id_str = jukit_id_str[(term_width - 4):]

    if wide_enough:
        bottom = "╰" + "─" * (w_frame - 2) + "╯"
        print(f"{_add_ws(term_width, bottom, center=True)}\u001b[0m\n")


# ---------------------------------------------------------------------------
# Output renderers
# ---------------------------------------------------------------------------

def render_stream(out):
    text = out.get("text", "")
    if isinstance(text, list):
        text = "".join(text)
    print(text, end="")


def render_execute_result(out):
    """Print '\\033[31mOut[\\033[32m<n>\\033[31m]: \\033[0m' followed by text/plain.
    Adds a newline before the text if it spans multiple lines, matching the
    legacy formatting in helpers/jukit_run/util.py:135-144."""
    count = out.get("execution_count", "")
    prompt = f"\u001b[31mOut[\u001b[32m{count}\u001b[31m]: \u001b[0m"
    txt = out.get("data", {}).get("text/plain", "")
    is_multi = False
    if isinstance(txt, str):
        is_multi = len(txt.split("\n")) > 1
    elif isinstance(txt, (list, tuple)) and txt:
        if len(txt) > 1:
            is_multi = True
        elif isinstance(txt[0], str) and len(txt[0].split("\n")) > 1:
            is_multi = True
    if is_multi:
        prompt += "\n"
    body = "".join(txt) if not isinstance(txt, str) else txt
    print(prompt + body)


def render_error(out):
    tb = out.get("traceback", [])
    if isinstance(tb, list):
        print("".join(tb))
    else:
        print(tb)


def render_display_data(out, max_width_factor):
    """Display image/png inline via sixel. text/html outputs only get
    their embedded base64 image extracted (legacy behavior); other HTML
    content like tables/formatted text is dropped (TODO)."""
    data = out.get("data", {})
    png_b64 = None
    if "image/png" in data:
        png_b64 = data["image/png"]
    elif "text/html" in data:
        html = data["text/html"]
        if isinstance(html, list):
            html = "".join(html)
        m = re.search(r"(?<=base64,)\S*(?=\")", html)
        if m:
            png_b64 = m.group(0)
    else:
        keys = list(data.keys())
        jukit_info(
            f"unsupported display_data keys: {keys}; supported: "
            "['image/png', 'text/html']",
            color="\u001b[33m",
        )
        return

    if png_b64 is None:
        return

    try:
        png_bytes = base64.b64decode(png_b64)
    except Exception as e:
        jukit_info(f"could not decode image base64: {e}", color="\u001b[31m")
        return

    emit_sixel_image(png_bytes, max_width_factor)


# ---------------------------------------------------------------------------
# Cell rendering
# ---------------------------------------------------------------------------

def render_cell(state, cell_id, is_md):
    clear_screen()
    term_width = _term_columns()
    print_cell_header(cell_id, term_width)

    if is_md:
        print("\u001b[33m[markdown cell]\u001b[0m")
        sys.stdout.flush()
        return

    # Always re-read the file so we pick up new outputs from in-flight cell
    # executions in the output pane.
    state["data"] = load_outhist(state["file"])
    if not state["data"]:
        jukit_info(
            f"no saved output found at {state['file']}",
            color="\u001b[33m",
        )
        return

    outputs = state["data"].get(cell_id)
    if outputs is None:
        jukit_info(
            "no saved output for this cell",
            color="\u001b[35m",
        )
        return

    for out in outputs:
        kind = out.get("output_type")
        if kind == "stream":
            render_stream(out)
        elif kind == "execute_result":
            render_execute_result(out)
        elif kind == "error":
            render_error(out)
        elif kind == "display_data":
            render_display_data(out, state["max_width_factor"])
        else:
            print(f"[unsupported output type: {kind}]")
    sys.stdout.flush()


def _term_columns():
    try:
        return os.get_terminal_size().columns
    except OSError:
        return 80


# ---------------------------------------------------------------------------
# Sixel image rendering
# ---------------------------------------------------------------------------
# get_terminal_pixels and the scale-arg math are ported from
# helpers/sixelcat/cat.py so the saved-output viewer scales images the same
# way the live-plot path does.
# ---------------------------------------------------------------------------

def get_terminal_pixels():
    """Get terminal size in pixels via the TIOCGWINSZ ioctl. Returns
    (width_px, height_px, px_per_row) on success, or None if /dev/tty is
    not available or the terminal didn't report pixel dimensions."""
    try:
        import fcntl
        import termios
        with open("/dev/tty", "rb") as tty:
            res = fcntl.ioctl(tty.fileno(), termios.TIOCGWINSZ, b"\x00" * 8)
            rows, cols, xpix, ypix = struct.unpack("HHHH", res)
            if xpix and ypix:
                return xpix, ypix, ypix // rows
    except Exception:
        pass
    return None


def get_png_dimensions(data):
    """Extract (width, height) from a PNG header. Returns (None, None) if
    the bytes don't look like a PNG."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    return None, None


def emit_sixel_image(png_bytes, max_width_factor):
    """Pipe PNG bytes through img2sixel and write the result to stdout.

    Scaling: if the source image is larger than the terminal in either
    dimension, pass --width or --height to img2sixel to fit. The
    max_width_factor controls how much wider than the terminal we'll let
    images grow when only width-constrained (matches sixelcat semantics)."""
    img_w, img_h = get_png_dimensions(png_bytes)
    term_size = get_terminal_pixels()

    scale_args = []
    if term_size and img_w and img_h:
        term_w, term_h, _ = term_size
        w_ratio = term_w / img_w
        h_ratio = term_h / img_h
        if w_ratio < 1.0 or h_ratio < 1.0:
            if w_ratio < h_ratio:
                scale_args = ["-w", str(int(term_w * max_width_factor))]
            else:
                scale_args = ["-h", str(term_h)]

    try:
        result = subprocess.run(
            ["img2sixel"] + scale_args,
            input=png_bytes,
            capture_output=True,
            check=True,
        )
    except FileNotFoundError:
        jukit_info(
            "img2sixel not found on $PATH; install libsixel-bin to render "
            "saved-plot outputs",
            color="\u001b[31m",
        )
        return
    except subprocess.CalledProcessError as e:
        jukit_info(
            f"img2sixel failed: {e.stderr.decode(errors='replace').strip()}",
            color="\u001b[31m",
        )
        return

    sys.stdout.buffer.write(result.stdout)
    sys.stdout.buffer.flush()


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="vim-jukit outhist viewer (zellij + sixel)"
    )
    parser.add_argument(
        "outhist_file",
        help="path to the *_outhist.json file to view",
    )
    parser.add_argument(
        "--max-width-factor",
        type=float,
        default=1.8,
        help="multiplier for max sixel image width relative to terminal width",
    )
    args = parser.parse_args()

    state = {
        "file": args.outhist_file,
        "data": {},
        "max_width_factor": args.max_width_factor,
    }
    state["data"] = load_outhist(state["file"])

    jukit_info("outhist viewer ready", color="\u001b[36m")

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        parts = line.split()
        cmd = parts[0]

        if cmd == "cell":
            if len(parts) < 2:
                jukit_info("usage: cell <id> [md]", color="\u001b[33m")
                continue
            cell_id = parts[1]
            is_md = len(parts) > 2 and parts[2] == "md"
            render_cell(state, cell_id, is_md)
        elif cmd == "file":
            if len(parts) < 2:
                jukit_info("usage: file <path>", color="\u001b[33m")
                continue
            state["file"] = parts[1]
            state["data"] = load_outhist(state["file"])
            jukit_info(
                f"switched outhist file to {state['file']}",
                color="\u001b[36m",
            )
        elif cmd == "clear":
            clear_screen()
        elif cmd == "quit":
            return
        else:
            jukit_info(f"unknown command: {cmd}", color="\u001b[33m")


if __name__ == "__main__":
    main()
