#!/bin/bash
# =============================================================================
# Personal install helper for a sixel-patched zellij build.
#
# This is the script the vim-jukit author uses on their own machine. It is
# NOT an officially supported installer:
#
#   * Linux/Debian only — uses `apt install` directly.
#   * Requires root (no `sudo` calls — run as root or wrap accordingly).
#   * Pins specific zellij and sixel-image commits; these may be stale by
#     the time you read this. Check upstream zellij first to see if native
#     sixel support has landed before running this script.
#   * Modifies files under ~/.cargo/bin and ~/zellij-build.
#
# vim-jukit's zellij backend works with vanilla zellij; only inline plotting
# (g:jukit_inline_plotting=1 with sixelcat) requires the patches in this
# script. If you only need code execution and not plots, ignore this file.
# =============================================================================
set -e

BUILD_DIR="$HOME/zellij-build"
INSTALL_DIR="$HOME/.cargo/bin"

echo "=== Installing prerequisites ==="
apt install -y protobuf-compiler pkg-config libssl-dev cargo git zip

PROTOC_VERSION="25.1"
PROTOC_ZIP="protoc-${PROTOC_VERSION}-linux-x86_64.zip"
curl -LO "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${PROTOC_ZIP}"
unzip -o "$PROTOC_ZIP" -d /usr/local bin/protoc
unzip -o "$PROTOC_ZIP" -d /usr/local 'include/*'
rm "$PROTOC_ZIP"


curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
. "$HOME/.cargo/env"

echo "=== Uninstalling existing zellij ==="
cargo uninstall zellij 2>/dev/null || echo "No cargo-installed zellij found"

echo "=== Setting up build directory ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=== Cloning repositories ==="
#git clone --depth 1 https://github.com/zellij-org/zellij.git
#git clone --depth 1 https://github.com/zellij-org/sixel-image.git
git clone --depth 1 https://github.com/zellij-org/zellij.git
cd zellij
git fetch --depth 1 origin 8aba80ebcc8cc22c455ebcf377ef2793c459a4e3
git checkout 8aba80ebcc8cc22c455ebcf377ef2793c459a4e3
cd ..

git clone --depth 1 https://github.com/zellij-org/sixel-image.git
cd sixel-image
git fetch --depth 1 origin 29e6deb2da3dc9771f6bc4f4362b63cbbe3ba043
git checkout 29e6deb2da3dc9771f6bc4f4362b63cbbe3ba043
cd ..

echo "=== Patching sixel-image (aspect ratio fix) ==="
sed -i 's/\\u{1b}Pq/\\u{1b}P9;1q/g' sixel-image/src/sixel_serializer.rs

echo "=== Patching sixel.rs ==="
sed -i 's/image_pixel_size\.0,/image_pixel_size.0 \/ 2,/g' zellij/zellij-server/src/panes/sixel.rs

sed -i 's/sixel_image\.serialize_range(pixel_x, pixel_y, pixel_width, pixel_height)/sixel_image.serialize_range(pixel_x, pixel_y * 2, pixel_width, pixel_height * 2)/g' zellij/zellij-server/src/panes/sixel.rs

sed -i 's/let sixel_image_pixel_width = if sixel_image_pixel_rect\.x/let sixel_image_pixel_width = sixel_image_pixel_rect.width; \/\/ DISABLED CLIPPING\n    let _sixel_image_pixel_width_DISABLED = if sixel_image_pixel_rect.x/g' zellij/zellij-server/src/panes/sixel.rs

echo "=== Patching grid.rs ==="
sed -i 's/self\.move_cursor_down_by_pixels(image_pixel_height);/self.move_cursor_down_by_pixels(image_pixel_height \/ 2);/g' zellij/zellij-server/src/panes/grid.rs

echo "=== Patching zellij to use local sixel-image ==="
echo '
[patch.crates-io]
sixel-image = { path = "../sixel-image" }' >> zellij/Cargo.toml

echo "=== Detecting wasm target ==="
cd zellij
WASM_TARGET=$(grep -roh 'wasm32-wasi[p0-9]*' --include="*.toml" | head -1)
echo "Repo uses: $WASM_TARGET"
rustup target add "$WASM_TARGET" || rustup target add wasm32-wasip1

echo "=== Building zellij (this takes a while) ==="
cargo xtask build --release

echo "=== Installing to $INSTALL_DIR ==="
cp target/release/zellij "$INSTALL_DIR/zellij"

echo "=== Done! ==="
zellij --version
