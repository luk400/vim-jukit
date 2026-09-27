#!/usr/bin/env python3
import importlib
import io
import pathlib
import sys
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPERS = ROOT / "helpers"
sys.path.insert(0, str(HELPERS))

backend = importlib.import_module("matplotlib-backend-kitty-protocol")

import matplotlib
matplotlib.use("module://matplotlib-backend-kitty-protocol", force=True)
import matplotlib.pyplot as plt

capture = io.StringIO()
with patch.object(backend, "_upload_to_parent_nvim", return_value=None), \
     patch.object(backend, "_real_stdout", return_value=capture):
    plt.plot([0, 1, 2], [0, 1, 0])
    plt.show(scaling=0.5)

text = capture.getvalue()
assert "\U0010eeee" in text.lower() or "\U0010EEEE" in text
assert "\x1b[38;2;" in text
assert len(backend._ROW_DIACRITICS) == 64
print("ok: protocol backend emitted truecolor Kitty Unicode placeholders")
