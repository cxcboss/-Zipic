#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMAGE="$ROOT_DIR/Assets/AppIcon-source.png"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
OUTPUT_ICNS="$ROOT_DIR/Resources/AppIcon.icns"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "Missing icon source: $SOURCE_IMAGE" >&2
  exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

render_icon() {
  local size="$1"
  local name="$2"
  sips -s format png -z "$size" "$size" "$SOURCE_IMAGE" --out "$ICONSET_DIR/$name" >/dev/null
}

render_icon 16 "icon_16x16.png"
render_icon 32 "icon_16x16@2x.png"
render_icon 32 "icon_32x32.png"
render_icon 64 "icon_32x32@2x.png"
render_icon 128 "icon_128x128.png"
render_icon 256 "icon_128x128@2x.png"
render_icon 256 "icon_256x256.png"
render_icon 512 "icon_256x256@2x.png"
render_icon 512 "icon_512x512.png"
render_icon 1024 "icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
rm -rf "$ICONSET_DIR"

echo "Generated: $OUTPUT_ICNS"
