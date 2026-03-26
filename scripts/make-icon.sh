#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/make-icon.sh <input-image>
# Converts any image to a proper macOS .icns with transparent corners.
# Outputs to Resources/AppIcon.icns
#
# The script:
# 1. Makes the image square (1024x1024)
# 2. Flood-fills corners to remove background (handles gradients)
# 3. Applies macOS rounded-rect mask for clean edges
# 4. Generates all required icon sizes using magick (not sips, which drops alpha)
# 5. Converts to .icns via iconutil

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

# Step 1: Make square 1024x1024
magick "$INPUT" \
  -resize 1024x1024^ \
  -gravity center -extent 1024x1024 \
  "$WORK/square.png"

# Step 2: Remove background from corners using flood-fill.
# Use 20% fuzz to handle gradient backgrounds.
# Flood-fill from all four corners + midpoints of edges to catch gradients.
magick "$WORK/square.png" \
  -alpha set \
  -fuzz 20% \
  -fill none \
  -draw "color 0,0 floodfill" \
  -draw "color 1023,0 floodfill" \
  -draw "color 0,1023 floodfill" \
  -draw "color 1023,1023 floodfill" \
  -draw "color 512,0 floodfill" \
  -draw "color 512,1023 floodfill" \
  -draw "color 0,512 floodfill" \
  -draw "color 1023,512 floodfill" \
  "$WORK/nobg.png"

# Step 3: Apply macOS rounded-rect mask for clean edges.
cat > "$WORK/mask.svg" << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">
  <rect x="0" y="0" width="1024" height="1024"
        rx="225" ry="225" fill="white"/>
</svg>
SVG

magick "$WORK/mask.svg" -background none -resize 1024x1024! "$WORK/mask.png"

# Composite: use mask as alpha channel on the background-removed image
magick "$WORK/nobg.png" \( "$WORK/mask.png" -alpha extract \) \
  -compose DstIn -composite \
  "$WORK/final-1024.png"

# Step 4: Generate all iconset sizes using magick (preserves alpha, unlike sips)
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

gen() { magick "$WORK/final-1024.png" -resize "${1}x${1}" "$ICONSET/${2}.png"; }

gen 16   icon_16x16
gen 32   icon_16x16@2x
gen 32   icon_32x32
gen 64   icon_32x32@2x
gen 128  icon_128x128
gen 256  icon_128x128@2x
gen 256  icon_256x256
gen 512  icon_256x256@2x
gen 512  icon_512x512
gen 1024 icon_512x512@2x

# Step 5: Convert to .icns
mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

# Verify transparency
CORNER=$(magick Resources/AppIcon.icns[0] -format "%[pixel:p{0,0}]" info: 2>/dev/null || echo "unknown")
echo "✅ Icon saved to Resources/AppIcon.icns (corner pixel: $CORNER)"
