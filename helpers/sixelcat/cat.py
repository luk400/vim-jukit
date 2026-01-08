import sys
import os
import io
import subprocess
import tempfile
from matplotlib.backends.backend_agg import FigureCanvasAgg as FigureCanvas

from .config import _config


def get_terminal_pixels():
    """Get terminal size in pixels, or None."""
    try:
        import fcntl, termios, struct
        with open('/dev/tty', 'rb') as tty:
            res = fcntl.ioctl(tty.fileno(), termios.TIOCGWINSZ, b'\x00' * 8)
            rows, cols, xpix, ypix = struct.unpack('HHHH', res)
            if xpix and ypix:
                return xpix, ypix, ypix // rows
    except Exception:
        pass
    return None


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


def sixelcat(fig, dpi=150, fp=None):
    """Display matplotlib figure using sixel graphics at specified DPI."""
    if fp is None:
        fp = sys.stdout.buffer

    buf = figure_to_png(fig, dpi=dpi)
    img_w, img_h = get_png_dimensions(buf)

    term_size = get_terminal_pixels()
    
    scale_arg = []
    #display_h = img_h

    max_width_factor = _config['max_width_factor'] # decrease to make max image width smaller

    if term_size:
        term_w, term_h, pix_per_row = term_size
        w_ratio = term_w / img_w
        h_ratio = term_h / img_h
        
        if w_ratio < 1.0 or h_ratio < 1.0:
            # Need to scale down - use the more restrictive dimension
            if w_ratio < h_ratio:
                scale_arg = ['-w', str(int(term_w*max_width_factor))]
                #display_h = int(img_h * w_ratio)
            else:
                scale_arg = ['-h', str(term_h)]
                #display_h = term_h
    else:
        pix_per_row = 20

    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
        tmp.write(buf)
        tmp_path = tmp.name

    try:
        cmd = ['img2sixel'] + scale_arg + [tmp_path]
        sixel_data = subprocess.run(cmd, capture_output=True, check=True).stdout

        #CSI = b'\x1b['
        #display_rows = (display_h // pix_per_row) + 1
        #fp.write(b'\n' * display_rows)
        #fp.write(CSI + b'?25l')
        #fp.write(CSI + str(display_rows).encode() + b'F')
        #fp.flush()

        fp.write(sixel_data)
        fp.flush()

        #fp.write(CSI + str(display_rows).encode() + b'E')
        #fp.write(CSI + b'?25h\n')
        #fp.flush()
    except Exception as e:
        print(e)
    finally:
        os.unlink(tmp_path)
