# vim-jukit: Kitty graphics protocol backend for Ghostty

This patch keeps Jukit's terminal/window backend separate from its image backend.
On Ghostty, use the existing `nvimterm` split backend and send images with the
Kitty terminal graphics protocol through Neovim's outer TUI.

## Why this design

A process inside Neovim's `:terminal` cannot safely emit Kitty graphics APC
sequences directly to Ghostty: Neovim is the host application between the PTY
and the terminal emulator. Neovim 0.12 added `nvim_ui_send()`, which is the
correct path for emitting terminal escape sequences to the TUI host terminal.

The backend therefore:

1. renders Matplotlib output as PNG;
2. uploads the PNG to the outer terminal using Kitty graphics commands sent by
   `nvim_ui_send()`;
3. creates a Kitty virtual placement (`U=1`);
4. writes `U+10EEEE` Unicode placeholder cells to the Jukit REPL PTY, with the
   image ID encoded in 24-bit foreground color;
5. lets Neovim redraw those placeholder cells as ordinary terminal-buffer text,
   so Ghostty can render the image at the corresponding cells;
6. stores the PNG in Jukit's existing output-history format so history replay
   uses the same backend.

No Kitty executable, `kitten icat`, Kitty remote-control socket, or Kitty app is
required for the Ghostty path.

## Requirements

- Neovim 0.12 or newer.
- Ghostty with Kitty graphics protocol Unicode-placeholder support.
- `termguicolors` enabled in Neovim.
- Direct Ghostty session. The automatic backend intentionally disables itself
  inside tmux because tmux graphics passthrough is a separate transport problem.

## Configuration

The backend auto-detects a direct Ghostty session. Explicit configuration:

```vim
set termguicolors
let g:jukit_terminal = 'nvimterm'
let g:jukit_graphics_backend = 'kitty'
let g:jukit_inline_plotting = 1

" Approximate terminal cell height/width ratio used for plot sizing.
let g:jukit_kitty_cell_aspect = 2.0
```

`g:jukit_graphics_backend` accepts `kitty` or `none`. If left empty, Jukit
auto-detects Ghostty/Kitty from the terminal environment when Neovim is new
enough and `termguicolors` is active.

Existing `g:jukit_terminal = 'kitty'` behavior is not replaced. It continues to
use the original Kitty-specific split/window code and `kitten icat` backend.

## Apply

From the root of `gregborane/vim-jukit`:

```sh
git apply /path/to/0001-ghostty-kitty-protocol.patch
```

The patch adds:

- `autoload/jukit/graphics.vim`
- `lua/jukit/kitty_graphics.lua`
- `helpers/matplotlib-backend-kitty-protocol/__init__.py`

and modifies:

- `plugin/jukit.vim`
- `autoload/jukit/util.vim`
- `autoload/jukit/splits.vim`
- `helpers/jukit_run/util.py`

## Current constraints

- Unicode placeholder row indices in this implementation are capped at 64 rows;
  plot width can still span the terminal. This is enough for normal Jukit split
  sizes but can be expanded by vendoring more entries from Kitty's stable
  row/column diacritic table.
- Plot sizing does not query Kitty's `icat --print-window-size`, by design. It
  uses the PTY cell dimensions plus `g:jukit_kitty_cell_aspect`; adjust that
  value if plots look too tall or too wide with a particular font configuration.
- This bundle was Python-smoke-tested in the build environment, but that
  environment does not contain Neovim or Ghostty, so the complete TUI-to-Ghostty
  rendering path was not executable there.
