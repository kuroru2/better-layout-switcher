#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/make-icon.sh <input-image> [crop-size]
# Converts any image to a proper macOS .icns.
# Crops a square from center, applies rounded-rect mask, generates all sizes.
# Optional crop-size (default: 80% of smaller dimension) controls how tight the crop is.
# Outputs to Resources/AppIcon.icns

INPUT="${1:-}"
if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
  echo "Usage: $0 <input-image.png> [crop-size-px]"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Processing $INPUT..."

# Get source dimensions
read -r W H <<< "$(magick identify -format "%w %h" "$INPUT")"
SMALLER=$((W < H ? W : H))

# Crop size: use argument or default to 80% of smaller dimension
CROP="${2:-$((SMALLER * 80 / 100))}"
echo "  Source: ${W}x${H}, cropping center ${CROP}x${CROP}"

# Step 1: Crop center square, scale to 4096 for high-res masking
magick "$INPUT" \
  -gravity center -crop "${CROP}x${CROP}+0+0" +repage \
  -resize 4096x4096 \
  "$WORK/sq.png"

# Step 2: Rounded-rect mask at 4096px (anti-aliased)
cat > "$WORK/mask.svg" << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="4096" height="4096">
  <rect x="0" y="0" width="4096" height="4096" fill="black"/>
  <rect x="0" y="0" width="4096" height="4096" rx="900" ry="900" fill="white"/>
</svg>
SVG

magick "$WORK/mask.svg" "$WORK/mask.png"

# Step 3: Apply mask — white=keep, black=transparent
magick "$WORK/sq.png" "$WORK/mask.png" -alpha off -compose CopyOpacity -composite "$WORK/final.png"

# Step 4: Generate all icon sizes with Lanczos downscale
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

gen() { magick "$WORK/final.png" -filter Lanczos -resize "${1}x${1}" "$ICONSET/${2}.png"; }

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

echo "✅ Icon saved to Resources/AppIcon.icns"
