#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/make-icon.sh <input-image>
# Converts any image to a proper macOS .icns with the standard squircle mask.
# Outputs to Resources/AppIcon.icns

INPUT="${1:-}"
if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
  echo "Usage: $0 <input-image.png>"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Processing $INPUT..."

# Step 1: Resize to square 1024x1024 (fill, crop center if not square)
magick "$INPUT" \
  -resize 1024x1024^ \
  -gravity center -extent 1024x1024 \
  "$WORK/source-1024.png"

# Step 2: Apply the macOS squircle mask.
# macOS uses a continuous curvature shape (superellipse / squircle).
# We use a rounded rect with large radius as an approximation.
# The mask covers the full 1024x1024 — the source image should fill the frame.
cat > "$WORK/mask.svg" << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">
  <rect x="0" y="0" width="1024" height="1024"
        rx="225" ry="225" fill="white"/>
</svg>
SVG

magick "$WORK/mask.svg" -resize 1024x1024 "$WORK/mask.png"

# Apply mask — areas outside the squircle become transparent
magick "$WORK/source-1024.png" "$WORK/mask.png" \
  -alpha off -compose CopyOpacity -composite \
  "$WORK/icon-1024.png"

# Step 4: Generate iconset with all required sizes
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
done

# @2x variants
sips -z 32 32 "$WORK/icon-1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null 2>&1
sips -z 64 64 "$WORK/icon-1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null 2>&1
sips -z 256 256 "$WORK/icon-1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null 2>&1
sips -z 512 512 "$WORK/icon-1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null 2>&1
sips -z 1024 1024 "$WORK/icon-1024.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null 2>&1

# Step 5: Convert to .icns
mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

echo "✅ Icon saved to Resources/AppIcon.icns"
