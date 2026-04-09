import sys
import os
import io
import json
import subprocess
import tempfile

from .config import _config


# Fallback cell dimensions used when the multiplexer doesn't populate
# xpix/ypix in TIOCGWINSZ. These are rough estimates for a typical
# monospaced font at ~12pt; they're only used to scale the image in
# absence of authoritative pixel dimensions, so a small error here
# just means the image ends up slightly over- or under-sized.
_FALLBACK_CELL_W = 10
_FALLBACK_CELL_H = 20


# Cache of the last-seen "tiled visible" pane pixel dimensions. Updated
# on every render where zellij tells us the pane is in a tiled+visible
# state, and consumed when the pane is (temporarily) floating or
# suppressed so the rendered figure size doesn't collapse to zellij's
# default floating-pane layout. See _get_pane_pixel_dims.
_last_tiled_pixel_dims = None


# Cell-row footprint of the last image rendered by sixelcat(). Read by
# helpers/jukit_run/util.py:display_outputs after `plt.show(block=False)`
# returns, so the outhist frame's left bar can be drawn over the rows the
# image occupies via cursor positioning. 0 means "couldn't compute"
# (no terminal pixel info), in which case display_outputs skips the
# overlay and just leaves the bar on the image's first row.
_last_image_cell_rows = 0


def _read_pty_winsize():
    """Read TIOCGWINSZ from ``/dev/tty``.

    Returns ``(rows, cols, xpix, ypix)`` with any of them set to 0 if
    the terminal / multiplexer didn't populate the field, or ``None``
    if ``/dev/tty`` isn't accessible at all (e.g. no controlling tty).
    """
    try:
        import fcntl, termios, struct
        with open('/dev/tty', 'rb') as tty:
            res = fcntl.ioctl(tty.fileno(), termios.TIOCGWINSZ, b'\x00' * 8)
            return struct.unpack('HHHH', res)
    except Exception:
        return None


def _query_zellij_pane_dims():
    """Ask zellij for our jukit output pane's current geometry.

    Returns ``(content_rows, content_cols, is_tiled_visible)`` or
    ``None`` if the query failed, zellij isn't running, no
    ``sixelcat_pane_id`` is published in ``.jukit_info.json``, or the
    pane isn't in the list-panes output.

    Why query zellij instead of trusting ``TIOCGWINSZ``: when the user
    hides the output pane (``<leader>os`` while visible), the zellij
    backend does ``toggle-pane-embed-or-floating`` + ``hide-floating-
    panes``. The embed-to-floating toggle physically resizes the pty
    to zellij's default floating-pane geometry -- typically about half
    the tiled height with the same width. ``TIOCGWINSZ`` then reports
    those smaller dims, and any plot generated while hidden gets
    rendered for that smaller target. When the user re-tiles the pane
    the pre-baked sixel data can't grow to fill the (now larger) pane.
    list-panes exposes both the current geometry AND the floating/
    suppressed flags, which is what lets us distinguish "the pane
    genuinely has these dims right now" from "the pane has been
    temporarily reshaped by a hide toggle".

    Uses ``pane_content_rows``/``pane_content_columns`` (the area
    inside any frame chrome) since that's what the pty's own winsize
    corresponds to; using ``pane_rows``/``pane_columns`` would over-
    count by the frame border width.
    """
    info_file = _config.get('info_file')
    if not info_file or not os.path.isfile(info_file):
        return None
    try:
        with open(info_file, 'r') as f:
            data = json.load(f)
    except Exception:
        return None
    pane_id = data.get('sixelcat_pane_id')
    if pane_id is None:
        return None
    try:
        res = subprocess.run(
            ['zellij', 'action', 'list-panes', '--json', '--all'],
            capture_output=True, timeout=2, check=True,
        )
        panes = json.loads(res.stdout)
    except Exception:
        return None
    if not isinstance(panes, list):
        return None
    for p in panes:
        if p.get('is_plugin'):
            continue
        if p.get('id') != pane_id:
            continue
        rows = p.get('pane_content_rows') or p.get('pane_rows')
        cols = p.get('pane_content_columns') or p.get('pane_columns')
        if not rows or not cols:
            return None
        is_tiled_visible = (
            not p.get('is_floating', False)
            and not p.get('is_suppressed', False)
        )
        return rows, cols, is_tiled_visible
    return None


def get_terminal_pixels():
    """Get terminal size in pixels.

    Returns ``(xpix, ypix, pix_per_row)`` or ``None`` when we can't
    determine any of the three components.

    Resolution order:
      1. Ask zellij via ``list-panes --json`` for the jukit output
         pane's current content-area cell count. If zellij reports the
         pane is tiled+visible, treat those cell counts as
         authoritative, convert to pixels using per-cell sizes derived
         from ``TIOCGWINSZ``, cache the result in
         ``_last_tiled_pixel_dims``, and return it.
      2. If zellij reports the pane is floating or suppressed (hidden),
         reuse the cached last-tiled dims so matplotlib produces a
         figure sized for what the user will actually see once the
         pane is visible again.
      3. Fall back to ``TIOCGWINSZ`` itself -- its ``xpix``/``ypix`` if
         non-zero, otherwise a ``rows * _FALLBACK_CELL_H`` /
         ``cols * _FALLBACK_CELL_W`` estimate for multiplexers that
         don't propagate pixel dimensions to pane ptys.

    The zellij-first path is the robust fix for the "hidden-run-show
    produces a smaller figure" observation: the pty's own winsize
    follows the pane's physical shape through the embed→float toggle,
    and list-panes is the only data source that can tell us "this pane
    is currently floating" so we know to reuse the cached tiled size.
    """
    global _last_tiled_pixel_dims

    winsz = _read_pty_winsize()
    if winsz is None:
        rows = cols = xpix = ypix = 0
    else:
        rows, cols, xpix, ypix = winsz

    # Derive per-cell pixel dimensions. These are font-level
    # properties and stay stable across pane toggles, so we can use
    # them to convert zellij's cell counts to pixels even when the pty
    # is currently reporting the floating-pane shape.
    if rows and cols and xpix and ypix:
        pix_per_row = ypix // rows
        pix_per_col = xpix // cols
    else:
        pix_per_row = _FALLBACK_CELL_H
        pix_per_col = _FALLBACK_CELL_W

    # Primary path: ask zellij.
    zinfo = _query_zellij_pane_dims()
    if zinfo is not None:
        z_rows, z_cols, is_tiled_visible = zinfo
        if is_tiled_visible:
            tiled = (z_cols * pix_per_col,
                     z_rows * pix_per_row,
                     pix_per_row)
            _last_tiled_pixel_dims = tiled
            return tiled
        if _last_tiled_pixel_dims is not None:
            return _last_tiled_pixel_dims
        # else: no cache yet AND currently floating -- fall through
        # to the pty dims so we at least render something sane.

    # Fallback: TIOCGWINSZ-only path.
    if xpix and ypix and rows:
        return xpix, ypix, ypix // rows
    if rows and cols:
        return cols * _FALLBACK_CELL_W, rows * _FALLBACK_CELL_H, _FALLBACK_CELL_H
    return None


def _read_runtime_factor():
    """Read ``sixelcat_width_factor`` fresh from ``.jukit_info.json``.

    This runs on every render so that ``:call
    jukit#util#ipython_info_write({'sixelcat_width_factor': X})`` from
    vim takes effect immediately without restarting IPython. Falls back
    to ``_config['max_width_factor']`` (which was seeded by
    ``sixelcat.configure()`` at IPython startup) if the info file isn't
    reachable or doesn't contain the key.

    The info file path is set by ``%jukit_init`` via
    ``sixelcat.configure(info_file=self.info_file)`` -- see
    ``helpers/jukit_run/jukit_run.py``.
    """
    info_file = _config.get('info_file')
    if info_file and os.path.isfile(info_file):
        try:
            with open(info_file, 'r') as f:
                data = json.load(f)
            val = data.get('sixelcat_width_factor')
            if val is not None:
                return float(val)
        except Exception:
            pass
    return _config['max_width_factor']


def _debug_log(msg):
    """Append a line to /tmp/jukit_sixelcat.log iff JUKIT_SIXELCAT_DEBUG
    is set. Silent no-op otherwise. Used for ad-hoc investigation of
    sizing issues -- enable with ``let $JUKIT_SIXELCAT_DEBUG=1`` in vim
    BEFORE starting the IPython pane.
    """
    if not os.environ.get('JUKIT_SIXELCAT_DEBUG'):
        return
    try:
        import datetime
        with open('/tmp/jukit_sixelcat.log', 'a') as f:
            f.write(f"[{datetime.datetime.now().isoformat()}] {msg}\n")
    except Exception:
        pass


def get_png_dimensions(data):
    """Extract (width, height) from PNG header."""
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        import struct
        return struct.unpack('>II', data[16:24])
    return None, None


def figure_to_png(fig, dpi=150):
    """Convert matplotlib figure to PNG bytes."""
    if fig.canvas is None:
        from matplotlib.backends.backend_agg import FigureCanvasAgg
        FigureCanvasAgg(fig)
    with io.BytesIO() as buf:
        fig.savefig(buf, format='png', dpi=dpi)
        return buf.getvalue()


def sixelcat(fig, dpi=150, fp=None, **_kwargs):
    """Display matplotlib figure using sixel graphics at specified DPI.

    Scaling semantics (post-fix):
      ``max_width_factor`` is a fraction of the pane the image should
      fill. 1.0 fits the pane exactly (preserving aspect ratio), 0.8
      leaves a ~20% margin, 1.5 deliberately overshoots the pane
      (producing a cut-off image -- allowed but discouraged). The old
      formula only applied the factor in the width-constrained branch
      and defaulted to 1.8, which meant every width-constrained render
      was upscaled to ~1.8× the pane width and cut off; and changing
      the factor had zero visible effect in the height-constrained
      branch because that branch ignored it entirely.

    **_kwargs is accepted for forward-compatibility: __init__.py forwards
    annotations like ``sixel_width``/``sixel_height``/``use_passthrough`` from
    ``plt.show.__annotations__`` and we drop them silently for now. When we
    actually wire any of those features up, add them to the explicit signature.
    """
    global _last_image_cell_rows
    _last_image_cell_rows = 0

    if fp is None:
        fp = sys.stdout.buffer

    buf = figure_to_png(fig, dpi=dpi)
    img_w, img_h = get_png_dimensions(buf)

    term_size = get_terminal_pixels()
    factor = _read_runtime_factor()

    scale_arg = []
    if term_size and img_w and img_h:
        term_w, term_h, pix_per_row = term_size
        # Target: fit the image within (term_w * factor, term_h * factor)
        # preserving aspect ratio. The smallest of the two per-axis fit
        # ratios is the fit scale -- applying it to both dims guarantees
        # neither axis overflows the target box.
        target_w = term_w * factor
        target_h = term_h * factor
        scale = min(target_w / img_w, target_h / img_h)
        new_w = max(1, int(img_w * scale))
        new_h = max(1, int(img_h * scale))
        # Pass -w unconditionally whenever the computed new width
        # differs from native. img2sixel preserves aspect ratio when
        # only -w is given, so we get a proportional resize.
        if new_w != img_w:
            scale_arg = ['-w', str(new_w)]
        # Publish the image's terminal-row footprint so display_outputs
        # (helpers/jukit_run/util.py) can draw the outhist frame's left
        # bar over the rows the image will occupy. ceil-div: an image
        # taller than N*pix_per_row pixels lands on row N+1.
        if pix_per_row > 0:
            _last_image_cell_rows = (new_h + pix_per_row - 1) // pix_per_row

    _debug_log(
        f"img={img_w}x{img_h} term={term_size} factor={factor} "
        f"scale_arg={scale_arg} cell_rows={_last_image_cell_rows}"
    )

    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
        tmp.write(buf)
        tmp_path = tmp.name

    try:
        cmd = ['img2sixel'] + scale_arg + [tmp_path]
        sixel_data = subprocess.run(cmd, capture_output=True, check=True).stdout
        fp.write(sixel_data)
        fp.flush()
    except Exception as e:
        # Errors must go to stderr so they don't clobber the ipython output
        # stream that the user is watching in the output pane.
        print(f"[vim-jukit] sixelcat error: {e}", file=sys.stderr)
    finally:
        os.unlink(tmp_path)
