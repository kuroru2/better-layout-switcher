#!/usr/bin/env bash
set -euo pipefail

# Generates the bundled HDR video used by XDR Boost, via ffmpeg/libx264.
#
# We need a small HEVC-or-H.264 video tagged with HDR color metadata that
# macOS recognizes as "real HDR content" — that's what commits the display
# into HDR mode and lets the gamma-table multiply actually drive the panel
# past the SDR brightness cap.
#
# Recipe (confirmed working when compared against Vivid's hdr.mov):
#   - H.264 codec (NOT HEVC), Main profile, Level 3.1
#   - 1280×720, 8-bit 4:2:0, video range
#   - BT.2020 color primaries + ARIB STD-B67 (HLG) transfer + BT.2020 matrix
#   - Silent stereo AAC audio track alongside the video
#   - .mov container with the avc1 fourcc tag
#
# AVAssetWriter can match all of these as surface metadata but the encoded
# bitstream's VUI/SEI parameters end up different and DisplayServices doesn't
# unlock. libx264 emits proper HDR VUI directly into the SPS, which is what
# the OS reads.

OUT="${1:-Sources/FnLightSwitch/Resources/hdr.mov}"
mkdir -p "$(dirname "$OUT")"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found. Install with: brew install ffmpeg" >&2
  exit 1
fi

ffmpeg -y -hide_banner -loglevel warning \
  -t 0.1 -f lavfi -i "color=c=white:s=1280x720:rate=30,format=yuv420p" \
  -t 0.1 -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
  -c:v libx264 -profile:v main -level 3.1 \
  -x264-params "colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc:fullrange=off" \
  -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc \
  -color_range tv \
  -bf 2 -g 1 \
  -c:a aac -b:a 64k \
  -movflags +faststart -tag:v avc1 \
  -f mov "$OUT"

echo "==> Wrote $OUT ($(stat -f %z "$OUT") bytes)"
