#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_SVG="$REPO_ROOT/assets/icon/open-island-icon.svg"
OUT_DIR="${1:-$REPO_ROOT/dist/icon}"
ICONSET_DIR="$OUT_DIR/OpenIsland.iconset"
BASE_DIR="$OUT_DIR/render"
BASE_PNG="$BASE_DIR/open-island-icon.png"
ICNS_PATH="$OUT_DIR/OpenIsland.icns"

mkdir -p "$ICONSET_DIR" "$BASE_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

if [ ! -f "$SOURCE_SVG" ]; then
  echo "Missing source SVG: $SOURCE_SVG" >&2
  exit 1
fi

qlmanage -t -s 1024 -o "$BASE_DIR" "$SOURCE_SVG" >/dev/null 2>&1

if [ ! -f "$BASE_PNG" ]; then
  GENERATED_PNG="$(find "$BASE_DIR" -maxdepth 1 -name '*.png' | head -n 1)"
  if [ -z "$GENERATED_PNG" ]; then
    echo "Failed to rasterize SVG icon" >&2
    exit 1
  fi
  mv "$GENERATED_PNG" "$BASE_PNG"
fi

create_icon() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

create_icon 16 icon_16x16.png
create_icon 32 icon_16x16@2x.png
create_icon 32 icon_32x32.png
create_icon 64 icon_32x32@2x.png
create_icon 128 icon_128x128.png
create_icon 256 icon_128x128@2x.png
create_icon 256 icon_256x256.png
create_icon 512 icon_256x256@2x.png
create_icon 512 icon_512x512.png
create_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Generated icon assets:"
echo "$BASE_PNG"
echo "$ICNS_PATH"
