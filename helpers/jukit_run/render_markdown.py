"""Inline markdown cell rendering for vim-jukit's %jukit_out_hist magic.

Splits the cell source on dollar-delimited math segments and routes:
  - non-math chunks   -> rich.Markdown -> console.print (ANSI styled)
  - inline   $...$    -> _emit_math_image (PNG -> img2sixel)
  - display  $$...$$  -> _emit_math_image (larger font, PNG -> img2sixel)

Math rendering has two backends, selected at runtime:

  1. Full LaTeX (preferred): pdflatex + pdftoppm. Supports any LaTeX
     construct -- AMS environments (bmatrix, align, cases, etc.),
     custom packages, the works. Detected by checking that both
     binaries are on $PATH. ~500ms per render.

  2. matplotlib mathtext (fallback): a fast LaTeX subset that does
     NOT support \\begin{...}\\end{...} environments but covers
     fractions, integrals, sums, Greek, sub/superscripts, etc. Used
     when pdflatex/pdftoppm are missing OR when full LaTeX errors
     on a particular segment (so simple expressions still render).

Only invoked on zellij (gated on the vim side by g:jukit_terminal in
autoload/jukit/splits.vim), so we can assume img2sixel and a sixel-capable
terminal are normally present. If rich is not installed, we fall back to
printing the raw source so the user at least sees something instead of a
traceback.
"""

import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# SAFE: importing from sixelcat.cat does NOT trigger matplotlib backend
# registration. The module://sixelcat backend is only installed when
# matplotlib.use("module://sixelcat") runs (see autoload/jukit/splits.vim
# lines 174-179), and these helpers are plain pure-Python functions.
from sixelcat.cat import get_terminal_pixels, get_png_dimensions


# Matches any $$...$$ (display) or $...$ (inline) segment. DOTALL so
# display-math spanning multiple lines is captured. Non-greedy so adjacent
# math segments on the same line don't merge.
#
# LIMITATION: does not understand escaped dollars (\$). The design doc
# explicitly accepts this as a first cut -- rendering "\$5 and \$10" with
# backslashes is rare in markdown cells and can be fixed later with a
# smarter tokenizer.
MATH_RE = re.compile(r"(\$\$.+?\$\$|\$.+?\$)", flags=re.DOTALL)


# Cached availability check for the full-LaTeX pipeline. None = not yet
# detected; True/False = detection result. Computed once per process to
# avoid paying shutil.which() on every render.
_full_latex_available = None

# One-shot flag: True after we have already printed the "pdflatex not
# installed" hint. We only show it once per IPython process so the user
# isn't nagged on every cell.
_latex_warning_shown = False


def _has_full_latex():
    """Return True iff pdflatex AND pdftoppm are both on $PATH."""
    global _full_latex_available
    if _full_latex_available is None:
        _full_latex_available = (
            shutil.which("pdflatex") is not None
            and shutil.which("pdftoppm") is not None
        )
    return _full_latex_available


def _maybe_show_latex_warning():
    """Print a one-line dim hint about installing the full LaTeX stack.

    Only fires once per process. Uses ANSI dim (\\x1b[2m) so the message
    is visually subtle and doesn't compete with the rendered cell.
    """
    global _latex_warning_shown
    if _latex_warning_shown:
        return
    _latex_warning_shown = True
    sys.stdout.write(
        "\u001b[2m"
        "[vim-jukit] Full LaTeX renderer (pdflatex + pdftoppm) not "
        "installed; using matplotlib mathtext fallback (no \\begin{...} "
        "environments).\n"
        "  Install:  apt install texlive-latex-base "
        "texlive-latex-recommended texlive-fonts-recommended poppler-utils\n"
        "  Hide:     let g:jukit_show_latex_warning = 0"
        "\u001b[0m\n\n"
    )
    sys.stdout.flush()


def render_markdown_cell(md_source, max_width_factor=1.8,
                         show_latex_warning=True):
    """Render a markdown cell to stdout. Never raises."""
    if not md_source:
        return

    # Surface the install hint *before* we start rendering, so it
    # appears at the top of the cell output rather than tucked between
    # math images. Only when math will actually need fallback handling
    # AND the user hasn't asked us to be quiet.
    if show_latex_warning and MATH_RE.search(md_source) and not _has_full_latex():
        _maybe_show_latex_warning()

    try:
        from rich.console import Console
        from rich.markdown import Markdown
    except ImportError:
        # Graceful degradation: rich missing -> plain print. Tell the
        # user *why* this is happening so they can install rich. ANSI
        # yellow directly so the message stands out without depending
        # on rich itself.
        sys.stdout.write(
            "\u001b[33m[vim-jukit] rich not installed; falling back to "
            "raw markdown source. `pip install rich` in your IPython "
            "kernel's environment to enable styled rendering.\u001b[0m\n"
        )
        sys.stdout.write(md_source)
        sys.stdout.write("\n")
        sys.stdout.flush()
        return

    # force_terminal=True so rich emits ANSI even when stdout's TTY
    # detection is unreliable (which can happen inside a zellij pane
    # whose pty is being driven by `zellij action write-chars`).
    #
    # width is shrunk by 2 to leave room for the outhist frame's left
    # bar (`│ ` at column 1, see helpers/jukit_run/util.py:_LinePrefixWriter).
    # Without this, rich would wrap at full terminal width and the
    # LinePrefixWriter prepending 2 columns of bar would push every line
    # 2 columns past the right edge of the terminal.
    term_cols = shutil.get_terminal_size().columns
    console = Console(force_terminal=True, width=max(20, term_cols - 2))
    parts = MATH_RE.split(md_source)
    for part in parts:
        if not part:
            continue
        if MATH_RE.fullmatch(part):
            display_mode = part.startswith("$$")
            # Strip outer delimiters. "$$x$$" -> "x", "$x$" -> "x".
            math = part[2:-2] if display_mode else part[1:-1]
            math = math.strip()
            if not math:
                continue
            _emit_math_image(math, display_mode, max_width_factor)
        else:
            # Non-math segment: rich.Markdown handles headers, bold,
            # italic, lists, tables, blockquotes, fenced code blocks
            # (pygments highlighted), links, HTML (limited fidelity).
            try:
                console.print(Markdown(part))
            except Exception as e:
                # rich should never raise on valid markdown, but be
                # defensive: print raw on failure, keep going.
                print(f"[markdown render error: {e}]", file=sys.stderr)
                sys.stdout.write(part)
                sys.stdout.flush()


def _emit_math_image(math_src, display_mode, max_width_factor):
    """Render a math segment to PNG via the best available backend and
    emit as sixel. Tries pdflatex first if installed, then mathtext.
    Never raises.
    """
    png_bytes = None
    if _has_full_latex():
        png_bytes = _render_via_pdflatex(math_src, display_mode)
    if png_bytes is None:
        # Either pdflatex isn't installed, or it failed for this
        # segment. mathtext can still handle most everyday math.
        png_bytes = _render_via_mathtext(math_src, display_mode)
    if png_bytes is None:
        # Both renderers failed -- print the raw source so the user
        # at least sees what the math was supposed to be.
        delim = "$$" if display_mode else "$"
        sys.stdout.write(f"{delim}{math_src}{delim}\n")
        sys.stdout.flush()
        return
    _emit_png_as_sixel(png_bytes, max_width_factor)


def _render_via_pdflatex(math_src, display_mode):
    """Render math via pdflatex + pdftoppm. Returns PNG bytes or None.

    Wraps the math source in a `standalone` document with `varwidth` so
    the page is cropped to the content. amsmath/amssymb/amsfonts cover
    matrices, align, equation arrays, blackboard bold, calligraphic, etc.
    """
    # Display mode uses \[ \] so operators (sums, integrals) render in
    # display style with limits above/below, plus \Large to give it the
    # visual weight of a Jupyter display equation. Inline uses \( \).
    #
    # We DON'T pass a font-size option to standalone -- standalone
    # inherits from `article` which only accepts 10/11/12pt and warns
    # on anything else. \Large works without that constraint.
    if display_mode:
        body = "\\Large\n\\[\n" + math_src + "\n\\]"
    else:
        body = "\\(" + math_src + "\\)"

    tex = (
        "\\documentclass[border=2pt,varwidth]{standalone}\n"
        "\\usepackage{amsmath,amssymb,amsfonts}\n"
        "\\begin{document}\n"
        + body + "\n"
        "\\end{document}\n"
    )

    try:
        with tempfile.TemporaryDirectory(prefix="jukit_md_") as tmpdir:
            tmp = Path(tmpdir)
            tex_path = tmp / "math.tex"
            tex_path.write_text(tex)

            # pdflatex run. -interaction=nonstopmode prevents it from
            # blocking on errors; we still get a non-zero exit code
            # which check=True turns into CalledProcessError. Capture
            # output to suppress noise + retain it for error reporting.
            try:
                subprocess.run(
                    [
                        "pdflatex",
                        "-interaction=nonstopmode",
                        "-halt-on-error",
                        "-output-directory",
                        str(tmp),
                        str(tex_path),
                    ],
                    capture_output=True,
                    check=True,
                    timeout=30,
                )
            except subprocess.CalledProcessError as e:
                # pdflatex writes errors to stdout (yes, stdout). Trim
                # to the last few lines around the actual error message.
                msg = ""
                if e.stdout:
                    msg = e.stdout.decode("utf-8", "replace")
                    msg = _extract_pdflatex_error(msg)
                print(f"[pdflatex render failed: {msg}]", file=sys.stderr)
                return None
            except subprocess.TimeoutExpired:
                print("[pdflatex timeout (>30s)]", file=sys.stderr)
                return None

            pdf_path = tmp / "math.pdf"
            if not pdf_path.exists():
                print("[pdflatex produced no PDF]", file=sys.stderr)
                return None

            # pdftoppm: -r 150 matches the mathtext DPI for visual
            # consistency when both backends are used in the same cell.
            # -singlefile + a prefix produces <prefix>.png (no -1, -2
            # numeric suffix that you'd get with multi-page input).
            png_prefix = tmp / "math"
            try:
                subprocess.run(
                    [
                        "pdftoppm",
                        "-png",
                        "-r",
                        "150",
                        "-singlefile",
                        str(pdf_path),
                        str(png_prefix),
                    ],
                    capture_output=True,
                    check=True,
                    timeout=10,
                )
            except (subprocess.CalledProcessError,
                    subprocess.TimeoutExpired) as e:
                print(f"[pdftoppm failed: {e}]", file=sys.stderr)
                return None

            png_path = tmp / "math.png"
            if not png_path.exists():
                print("[pdftoppm produced no PNG]", file=sys.stderr)
                return None

            return png_path.read_bytes()
    except Exception as e:
        # Defensive catch-all: filesystem errors, perms, etc.
        print(f"[pdflatex pipeline error: {e}]", file=sys.stderr)
        return None


def _extract_pdflatex_error(log_text):
    """Pull the most useful line(s) from a pdflatex log dump.

    pdflatex logs are verbose. The actually-useful error usually starts
    with `! ` (a single bang) and is followed by a few lines of context.
    Return up to ~3 lines starting from the first `!` line. Falls back
    to the last 200 chars if no `!` line is found.
    """
    lines = log_text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("! "):
            return " | ".join(lines[i:i + 3])[:300]
    return log_text[-200:]


def _render_via_mathtext(math_src, display_mode):
    """Render math via matplotlib mathtext. Returns PNG bytes or None.

    Fast (~10ms per render) but limited to a LaTeX subset -- no
    \\begin{...}\\end{...} environments, no \\usepackage, no custom
    macros. Used as the fallback when pdflatex isn't installed.
    """
    try:
        # CRITICAL: use Figure + FigureCanvasAgg directly instead of
        # plt.figure()/plt.close(). plt.figure() would create the figure
        # under the *active* matplotlib backend, which on zellij is
        # "module://sixelcat". That backend emits figures to the terminal
        # on plt.show()/close events. We don't want that here -- we want
        # a plain Agg canvas we render ourselves and drop.
        from matplotlib.figure import Figure
        from matplotlib.backends.backend_agg import FigureCanvasAgg
    except ImportError:
        print("[mathtext render failed: matplotlib not available]",
              file=sys.stderr)
        return None

    fontsize = 18 if display_mode else 14
    fig = Figure(figsize=(0.01, 0.01))
    FigureCanvasAgg(fig)  # wires a canvas without touching pyplot
    fig.text(0, 0, f"${math_src}$", fontsize=fontsize)

    buf = io.BytesIO()
    try:
        fig.savefig(buf, format="png", bbox_inches="tight",
                    pad_inches=0.02, dpi=150)
    except Exception as e:
        # Malformed math, or LaTeX construct mathtext can't parse
        # (most commonly: \\begin{...} environments).
        print(f"[mathtext render failed: {e}]", file=sys.stderr)
        fig.clear()
        return None

    fig.clear()
    return buf.getvalue()


def _emit_png_as_sixel(png_bytes, max_width_factor):
    """Pipe PNG bytes through img2sixel and write to stdout. Never raises.

    Scaling logic adapted from sixelcat.cat.sixelcat (cat.py:63-75).

    If the surrounding outhist_frame is active (sys.stdout is a
    _LinePrefixWriter), routes the sixel data through
    `emit_image_with_bars` which pre-allocates the cyan `│ ` bar
    on every cell row the image will occupy and uses DECSC/DECRC
    around the sixel emission to position the cursor reliably
    after rendering. This avoids the older emit_image_prefix +
    emit_image_suffix protocol, which suffered from "row 2 of every
    image after the first has its bar missing" because zellij's
    post-sixel `move_cursor_down_by_pixels(image_pixel_height / 2)`
    has rounding drift between back-to-back images. See
    util.py:_LinePrefixWriter.emit_image_with_bars for full context.
    """
    img_w, img_h = get_png_dimensions(png_bytes)
    term_size = get_terminal_pixels()
    pix_per_row = 0
    new_w, new_h = img_w or 0, img_h or 0
    scale_args = []
    if term_size and img_w and img_h:
        term_w, term_h, pix_per_row = term_size
        w_ratio = term_w / img_w
        h_ratio = term_h / img_h
        if w_ratio < 1.0 or h_ratio < 1.0:
            if w_ratio < h_ratio:
                new_w = int(term_w * max_width_factor)
                scale_args = ["-w", str(new_w)]
                # img2sixel preserves aspect ratio when only -w is
                # given, so the resulting height is proportional.
                new_h = int(round(img_h * new_w / img_w))
            else:
                new_h = term_h
                scale_args = ["-h", str(new_h)]
                new_w = int(round(img_w * new_h / img_h))

    # CRITICAL: cell_rows must reflect the ACTUAL visual rendered
    # height, which is NOT just ceil(new_h / pix_per_row). The
    # sixel-image deserializer in zellij encodes pixel data in
    # 6-row strips (each sixel "line" = 6 vertical pixels), and
    # `make_sure_six_lines_exist_after_cursor` rounds the pixel
    # buffer up to a multiple of 6. So an 86-pixel PNG becomes a
    # 90-pixel sixel image after deserializer padding. The patches
    # in helpers/sixelcat/install_and_patch_zellij.sh then store
    # `pixel_rect.height = padded/2 = 45` and re-serialize with
    # `pixel_height * 2 = 90`, which is what the user's terminal
    # actually paints. So:
    #   visual cells = ceil(((new_h + 5) // 6) * 6 / pix_per_row)
    #
    # For 81 px (integral): padded = 84 → ceil(84/22) = 4. Same as
    # naive ceil(81/22) = 4 -- no difference.
    # For 86 px (matrix):   padded = 90 → ceil(90/22) = 5. NAIVE
    # ceil(86/22) = 4 -- off by ONE, leaving the 5th visual row of
    # every matrix-style image without a `│ ` bar.
    #
    # This bug only manifests when new_h is in a "sixel-padding
    # gap": new_h % 6 != 0 AND new_h % 22 is in the upper half of
    # [0, 21] such that padding pushes it across a cell boundary.
    cell_rows = 0
    if pix_per_row > 0 and new_h > 0:
        sixel_padded_h = ((new_h + 5) // 6) * 6
        cell_rows = (sixel_padded_h + pix_per_row - 1) // pix_per_row

    try:
        result = subprocess.run(
            ["img2sixel"] + scale_args,
            input=png_bytes,
            capture_output=True,
            check=True,
        )
    except FileNotFoundError:
        # img2sixel not installed. Tell the user once.
        print("[img2sixel not found; cannot emit math image]",
              file=sys.stderr)
        return
    except subprocess.CalledProcessError as e:
        print(f"[img2sixel error: {e}]", file=sys.stderr)
        return

    # Debug log: append per-image dims so we can match user reports
    # to actual cell_rows values without needing them to read every
    # variable. Disabled by default; flip the env var to opt in.
    if os.environ.get("JUKIT_RENDER_MD_DEBUG"):
        try:
            import datetime as _dt
            with open("/tmp/jukit_render_md_debug.log", "a") as _f:
                naive_cells = (new_h + pix_per_row - 1) // pix_per_row if pix_per_row > 0 and new_h > 0 else 0
                _f.write(
                    f"[{_dt.datetime.now().isoformat()}] "
                    f"img_w={img_w} img_h={img_h} new_w={new_w} new_h={new_h} "
                    f"term_size={term_size} pix_per_row={pix_per_row} "
                    f"naive_cells={naive_cells} cell_rows={cell_rows} "
                    f"sixel_bytes={len(result.stdout)}\n"
                )
        except Exception:
            pass

    # Detect the _LinePrefixWriter via duck typing on the new
    # method; this avoids importing the private class from util.py
    # and also makes the fall-back path explicit when render_markdown
    # is somehow called outside an outhist_frame context.
    wrapped = sys.stdout if hasattr(sys.stdout, "emit_image_with_bars") else None

    if wrapped is not None:
        wrapped.emit_image_with_bars(cell_rows, result.stdout)
    else:
        # Standalone (no frame) path: just emit the sixel + newline.
        sys.stdout.buffer.write(result.stdout)
        sys.stdout.buffer.write(b"\n")
        sys.stdout.buffer.flush()
