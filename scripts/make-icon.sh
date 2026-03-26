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

# Step 1: Trim whitespace/transparent edges, make square 1024x1024
magick "$INPUT" -trim +repage \
  -gravity center -background none -extent 1024x1024 \
  "$WORK/source-1024.png"

# Step 2: Create the macOS squircle mask
# macOS uses a continuous curvature shape (squircle), not a simple rounded rect.
# We approximate it with SVG's smoothly curved path at 1024x1024.
cat > "$WORK/mask.svg" << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">
  <path d="
    M 512 0
    C 776 0, 880 0, 944 40
    C 984 64, 1000 100, 1014 148
    C 1024 184, 1024 248, 1024 512
    C 1024 776, 1024 840, 1014 876
    C 1000 924, 984 960, 944 984
    C 880 1024, 776 1024, 512 1024
    C 248 1024, 144 1024, 80 984
    C 40 960, 24 924, 10 876
    C 0 840, 0 776, 0 512
    C 0 248, 0 184, 10 148
    C 24 100, 40 64, 80 40
    C 144 0, 248 0, 512 0
    Z
  " fill="white"/>
</svg>
SVG

# Convert SVG mask to PNG
magick "$WORK/mask.svg" -resize 1024x1024 "$WORK/mask.png"

# Step 3: Apply mask to source image
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
