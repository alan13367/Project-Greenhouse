#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/assets/Project Greenhouse Icon.png"
OUTPUT_DIR="$ROOT_DIR/apps/GreenhouseMac/Resources"
MASTER_ICON="$OUTPUT_DIR/AppIcon-1024.png"
OUTPUT_ICON="$OUTPUT_DIR/AppIcon.icns"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/greenhouse-icon.XXXXXX")"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick is required to regenerate the app icon." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Source icon not found: $SOURCE_ICON" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$ICONSET_DIR"

# The supplied artwork has a black, edge-connected surround. Remove only that
# contiguous surround so dark interior details remain intact, then trim and fit
# the visible artwork within a transparent 1024-point master.
magick "$SOURCE_ICON" \
  -alpha on \
  -bordercolor black \
  -border 1 \
  -fuzz 8% \
  -fill none \
  -draw "alpha 0,0 floodfill" \
  -shave 1x1 \
  -trim +repage \
  -filter Lanczos \
  -resize "920x920>" \
  -gravity center \
  -background none \
  -extent 1024x1024 \
  "$MASTER_ICON"

make_icon() {
  local size="$1"
  local name="$2"
  magick "$MASTER_ICON" -filter Lanczos -resize "${size}x${size}" "$ICONSET_DIR/$name"
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil --convert icns --output "$OUTPUT_ICON" "$ICONSET_DIR"

[[ "$(sips -g pixelWidth "$MASTER_ICON" | awk '/pixelWidth/ {print $2}')" == "1024" ]]
[[ "$(sips -g pixelHeight "$MASTER_ICON" | awk '/pixelHeight/ {print $2}')" == "1024" ]]
[[ "$(sips -g hasAlpha "$MASTER_ICON" | awk '/hasAlpha/ {print $2}')" == "yes" ]]

echo "Generated $OUTPUT_ICON"
