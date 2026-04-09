import io, json, base64, re, os, sys, time
import contextlib
from matplotlib import pyplot as plt
import matplotlib.image as mpimg
from typing import List
from IPython.core.interactiveshell import InteractiveShell

MODULE_PATH = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(MODULE_PATH, "..", ".encodings"), "r") as f:
    ENCODING = f.read().strip()


KiB = 2 ** 10
MiB = 2 ** 20


# Outhist display frame: a left-only border drawn around the saved-output
# render in the IPython output pane. The bar is open on the right side --
# the user wants outputs to extend past the horizontal lines if they're
# long -- so every body line gets a "│ " prefix and the top/separator/
# bottom rows end with an arrow instead of a corner.
_OUTHIST_BAR_INNER = 14
_CYAN = "\u001b[36m"
_RESET = "\u001b[0m"
_OUTHIST_TOP = f"{_CYAN}╭{'─' * _OUTHIST_BAR_INNER}➞{_RESET}"
_OUTHIST_SEP = f"{_CYAN}├{'─' * _OUTHIST_BAR_INNER}➞{_RESET}"
_OUTHIST_BTM = f"{_CYAN}╰{'─' * _OUTHIST_BAR_INNER}➞{_RESET}"
# Body prefix is two visible columns wide (`│` + space). The cyan ANSI
# wrappers are invisible to the cursor; consumers (rich, etc.) can subtract
# OUTHIST_PREFIX_WIDTH from terminal columns to avoid line-wrap overflow.
_OUTHIST_PREFIX = f"{_CYAN}│ {_RESET}"
OUTHIST_PREFIX_WIDTH = 2


def jukit_info(text: str, color: str = "\u001b[31m"):
    print(color + "[vim-jukit] " + text + "\u001b[0m")


def catch_load_json(
    file: str, ntries_left: int = 10, time_between: float = 0.5
) -> dict:
    """in case file is trying to be loaded while it is being written to by
    another process. if it still can't be loaded after `ntries_left` then
    it is assumed that it is corrupted and replaced with empty json"""

    try:
        with open(file, "r", encoding=ENCODING) as f:
            info = json.load(f)
    except json.JSONDecodeError:
        jukit_info(f"JSONDecodeError, number of tries left: {ntries_left}")
        if ntries_left > 0:
            time.sleep(time_between)
            info = catch_load_json(file, ntries_left=ntries_left - 1)
        else:
            jukit_info("JSON file not readable, replacing with empty json!")
            info = {}
            with open(file, "w+", encoding=ENCODING) as f:
                json.dump(info, f)

    return info


def hide_prompt(shell: InteractiveShell):
    x, _ = os.get_terminal_size()
    sys.stdout.write("\033[A" + " " * x + "\033[A")


def display_outhist_header(title: str = "Last Output"):
    """Print the top of the outhist frame: top corner + title + separator.

    The frame is open on the right side (no right-hand border): we draw
    a cyan corner, dashes, and a `➞` to signal "the bar continues but
    the line is free to extend past it". Used in pair with
    display_outhist_footer via the outhist_frame() context manager so
    the entire saved-output render is visually distinguished from the
    rest of the IPython output stream.

    `title` is shown in the title row -- defaults to "Last Output" for
    code-cell renders. Markdown-cell renders pass "Markdown" so the
    user knows at a glance which kind of cell they're looking at.
    """
    print()
    print(_OUTHIST_TOP)
    print(f"{_CYAN}│ {title}{_RESET}")
    print(_OUTHIST_SEP)


def display_outhist_footer():
    """Print the bottom of the outhist frame.

    Mirrors display_outhist_header: same width and arrow tail, with
    `╰` at the bottom-left corner.
    """
    print(_OUTHIST_BTM)
    print()


class _LinePrefixWriter:
    """Stdout wrapper that prepends a fixed prefix to every new line.

    Used by outhist_frame() for the body of the outhist render: every
    print() that goes through sys.stdout gets the cyan `│ ` bar at
    column 1. Sixel images write to sys.stdout.buffer directly and
    bypass this wrapper, so we expose emit_image_prefix /
    emit_image_suffix to draw the bar around image rows via cursor
    positioning instead.

    `\\r` is treated as a line start so tqdm-style progress bars (which
    overwrite the current line) still get the prefix on each redraw.
    """

    def __init__(self, wrapped, prefix):
        self._wrapped = wrapped
        self._prefix = prefix
        self._at_line_start = True

    def write(self, text):
        if not text:
            return 0
        out = []
        for ch in text:
            if self._at_line_start:
                out.append(self._prefix)
                self._at_line_start = False
            out.append(ch)
            if ch == '\n' or ch == '\r':
                self._at_line_start = True
        self._wrapped.write(''.join(out))
        return len(text)

    def flush(self):
        self._wrapped.flush()

    def isatty(self):
        if hasattr(self._wrapped, 'isatty'):
            return self._wrapped.isatty()
        return False

    def __getattr__(self, attr):
        # Pass-through for buffer (sixel writes), encoding, fileno, etc.
        return getattr(self._wrapped, attr)

    def emit_image_prefix(self):
        """Position the cursor for an upcoming sixel image.

        Ensures we're at column 1 of a fresh line, then writes the
        prefix bytes directly through the underlying buffer. We go via
        the buffer (bypassing the TextIOWrapper) so the prefix and the
        sixel data that follows it share the same io path -- otherwise
        the TextIOWrapper could buffer the prefix and the binary write
        would jump ahead of it. Cursor ends at col 3, ready for sixel.
        """
        if not self._at_line_start:
            self._wrapped.write('\n')
        self._wrapped.flush()
        buf = getattr(self._wrapped, 'buffer', None)
        if buf is not None:
            buf.write(self._prefix.encode('utf-8'))
            buf.flush()
        else:
            self._wrapped.write(self._prefix)
            self._wrapped.flush()
        self._at_line_start = False

    def emit_image_suffix(self, image_cell_rows):
        """Draw the prefix bar on the remaining (image_cell_rows-1) rows
        of a just-emitted sixel image.

        Assumes the cursor is one row below the image (the typical
        post-sixel state). The horizontal cursor column after sixel is
        NOT reliable: zellij in particular leaves the cursor at the
        column where the sixel started -- col 3 here, just past the
        `│ ` prefix written by emit_image_prefix. `\\033[<n>A` (cursor
        up) preserves the column per spec, so without an explicit `\\r`
        the first loop iteration writes its `│ ` at col 3 of the
        second image row instead of col 1, producing a 2-column
        indent that obscures the first plot column. The leading `\\r`
        below snaps to col 1 before the loop runs.

        For each of the H-1 image rows that don't yet have a bar (the
        first row was handled by emit_image_prefix), we cursor-up,
        snap to col 1, then write `│ ` + cursor-down + CR per row.
        Cursor ends at col 1 of the row immediately below the image
        so the next output flows naturally.

        NOTE: this prefix/suffix protocol depends on zellij landing the
        cursor exactly `image_cell_rows` rows below the image start
        after sixel emission. With the patches in
        helpers/sixelcat/install_and_patch_zellij.sh that's only
        reliable for the FIRST image in a sequence -- subsequent
        images suffer from rounding drift in
        `move_cursor_down_by_pixels(image_pixel_height / 2)` and the
        cursor lands one row off, leaving row 2 of image 2+ without
        a bar. For those cases use emit_image_with_bars instead, which
        pre-allocates the bars before sixel emission and uses
        DECSC/DECRC to escape post-sixel cursor accounting entirely.
        Display_outputs (code-cell plot path) still uses prefix/suffix
        because it doesn't know cell_rows until after sixelcat runs.
        """
        if image_cell_rows < 2:
            self._at_line_start = True
            return
        n = image_cell_rows - 1
        buf = getattr(self._wrapped, 'buffer', None)
        if buf is not None:
            buf.write(f"\033[{n}A\r".encode('utf-8'))
            seq = (self._prefix + "\033[B\r").encode('utf-8')
            for _ in range(n):
                buf.write(seq)
            buf.flush()
        else:
            self._wrapped.write(f"\033[{n}A\r")
            for _ in range(n):
                self._wrapped.write(self._prefix + "\033[B\r")
            self._wrapped.flush()
        self._at_line_start = True

    def emit_image_with_bars(self, image_cell_rows, sixel_bytes):
        """Emit a sixel image bracketed by `image_cell_rows` of `│ ` bar.

        This is the bar-handling protocol of choice when the caller
        already knows the visual cell-row footprint of the image
        BEFORE emitting the sixel data (which is the case for the
        markdown math-image renderer in render_markdown.py, where the
        PNG dimensions are known up front).

        How it differs from emit_image_prefix + emit_image_suffix:
        instead of "write 1 bar, emit sixel, navigate back up to draw
        bars on rows 2..H", we PRE-ALLOCATE all H bars BEFORE sixel
        emission, then use DECSC/DECRC (`\\033[s` / `\\033[u`, supported
        by zellij) to bracket the sixel data, and finally an explicit
        `\\033[<H>B` cursor-down + `\\r` to land at col 1 of the row
        immediately following the image's visual footprint.

        Why this is necessary: zellij's post-sixel
        `move_cursor_down_by_pixels(image_pixel_height / 2)` (see
        helpers/sixelcat/install_and_patch_zellij.sh) doesn't reliably
        match the image's visual footprint -- the patched halving
        introduces rounding error so the cursor sometimes lands one
        row INSIDE the visual image rather than below it. The bug
        symptom is "row 2 of every image after the first has its `│ `
        missing" (the cursor-up arithmetic in emit_image_suffix
        compounds the drift between images). DECSC/DECRC sidesteps
        this entirely: we save before sixel, restore after, then move
        down by EXACTLY `image_cell_rows`, so the post-sixel cursor
        position is irrelevant.

        `image_cell_rows` should be the visual cell-row footprint of
        the rendered image, computed via
        `ceil(rendered_pixel_height / pix_per_row)`. For the math
        image case, that's just `(new_h + pix_per_row - 1) //
        pix_per_row` from the PNG dimensions after scaling.
        """
        if image_cell_rows < 1:
            # Unknown size: fall back to the old single-bar prefix +
            # raw sixel write + CR. No suffix bars (we don't know
            # how many to draw).
            self.emit_image_prefix()
            buf = getattr(self._wrapped, 'buffer', None)
            if buf is not None:
                buf.write(sixel_bytes)
                buf.write(b"\r")
                buf.flush()
            else:
                self._wrapped.write(sixel_bytes.decode('latin-1'))
                self._wrapped.write("\r")
                self._wrapped.flush()
            self._at_line_start = True
            return

        # Open a fresh line if not already at one. This goes through
        # _wrapped.write (TextIOWrapper), so the kernel's ONLCR will
        # translate `\n` to `\r\n` before it hits the pty.
        if not self._at_line_start:
            self._wrapped.write('\n')
        self._wrapped.flush()

        buf = getattr(self._wrapped, 'buffer', None)
        if buf is None:
            # Should not happen with a real stdout pty, but be
            # defensive: degrade to plain text writes.
            for _ in range(image_cell_rows):
                self._wrapped.write(self._prefix)
                self._wrapped.write('\n')
            self._wrapped.write(sixel_bytes.decode('latin-1'))
            self._wrapped.flush()
            self._at_line_start = True
            return

        prefix_bytes = self._prefix.encode('utf-8')

        # Phase 1: write `image_cell_rows` rows of bar prefix,
        # separated by `\n`. After this, cursor is at row R+H-1 col 3
        # (assuming ONLCR-translated `\n` lands cursor at col 1 of
        # the next row, which is the standard cooked-mode behavior
        # for ipython's pty).
        for i in range(image_cell_rows):
            if i > 0:
                buf.write(b"\n")
            buf.write(prefix_bytes)

        # Phase 2: cursor up by H-1 to land back at row R col 3.
        if image_cell_rows > 1:
            buf.write(f"\033[{image_cell_rows - 1}A".encode('utf-8'))

        # Phase 3: save cursor (row R col 3) with DECSC. zellij also
        # accepts `\033[s` (CSI s) which calls the same handler.
        buf.write(b"\033[s")

        # Phase 4: emit sixel data. The image renders starting at
        # row R col 3 (col 1-2 of every image row already has the
        # bar from phase 1). zellij will advance the cursor by some
        # amount via `move_cursor_down_by_pixels`, but we don't care
        # how much -- the next phase restores from the saved
        # position, sidestepping any rounding drift in zellij's
        # cell-row accounting.
        buf.write(sixel_bytes)

        # Phase 5: restore cursor to (row R col 3) -- the position
        # right before sixel emission.
        buf.write(b"\033[u")

        # Phase 6: explicit cursor-down by `image_cell_rows` to land
        # at (row R+H col 3) -- the row right after the image's
        # visual footprint. cursor-down preserves col, so we're
        # still at col 3.
        buf.write(f"\033[{image_cell_rows}B".encode('utf-8'))

        # Phase 7: snap to col 1 of (row R+H). Subsequent text
        # output through the wrapper will start here with a fresh
        # bar prefix.
        buf.write(b"\r")
        buf.flush()
        self._at_line_start = True


@contextlib.contextmanager
def outhist_frame(title: str = "Last Output"):
    """Context manager that wraps a body of output in the outhist frame.

    Prints the cyan header (top corner + title + separator), swaps
    sys.stdout for a _LinePrefixWriter so every body line gets the
    `│ ` prefix at column 1, yields the wrapper (so the caller can
    grab it for image-row prefixing if needed), then prints the cyan
    footer on exit.

    `title` defaults to "Last Output" for code-cell renders. The
    markdown-cell branch in jukit_out_hist passes "Markdown" so the
    user can tell at a glance which kind of cell they're looking at.

    Used by jukit_out_hist for both code-output and markdown-cell
    renders so the visual framing is consistent across cell types.
    """
    display_outhist_header(title)
    orig_stdout = sys.stdout
    wrapped = _LinePrefixWriter(orig_stdout, _OUTHIST_PREFIX)
    sys.stdout = wrapped
    try:
        yield wrapped
    finally:
        sys.stdout = orig_stdout
        # Make sure the footer doesn't land at the end of an
        # unterminated body line (e.g. when the last output was an
        # image whose suffix left the cursor at col 1 but the
        # _at_line_start tracking thinks we're mid-line).
        if not wrapped._at_line_start:
            sys.stdout.write('\n')
        display_outhist_footer()


def display_outputs(outputs: List[dict], term: str, shell: InteractiveShell):
    # If we're inside an outhist_frame() context, sys.stdout is a
    # _LinePrefixWriter and we should ask it to draw bars around image
    # rows (text rows are handled automatically by its write()).
    wrapped = sys.stdout if isinstance(sys.stdout, _LinePrefixWriter) else None
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

                # zellij is in this list because the sixelcat backend
                # renders plots inline; the [PLOT] placeholder would be
                # redundant on top of the actual rendered image.
                if term not in ["kitty", "tmux", "zellij"]:
                    jukit_info("PLOT", color="\u001b[33m")

                # Open a fresh line and draw the bar on the image's
                # first row before the sixel emission. emit_image_prefix
                # writes through the underlying buffer so it shares the
                # io path with the upcoming sixel data and stays in
                # order with it.
                if wrapped is not None:
                    wrapped.emit_image_prefix()

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

                # Draw the bar on the remaining image rows. Sixelcat
                # publishes the cell-row footprint of the most-recently
                # rendered figure as `_last_image_cell_rows`; we read
                # it without an explicit `import sixelcat` because
                # sixelcat is only loaded on zellij. For other backends
                # the module isn't on sys.modules and we silently skip
                # the bar overlay.
                if wrapped is not None:
                    cell_rows = 0
                    sc_cat = sys.modules.get("sixelcat.cat")
                    if sc_cat is not None:
                        cell_rows = getattr(sc_cat, "_last_image_cell_rows", 0)
                    wrapped.emit_image_suffix(cell_rows)
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
