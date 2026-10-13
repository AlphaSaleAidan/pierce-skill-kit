#!/usr/bin/env bash
# RGBA PNG sequence -> VP9 alpha webm (Chrome/Firefox/Edge) + HEVC-alpha mov attempt (Safari).
# Usage: encode_alpha.sh <png_dir> <out_basename> [fps]
set -euo pipefail
DIR=$1; OUT=$2; FPS=${3:-30}
ffmpeg -v error -y -framerate "$FPS" -i "$DIR/f%05d.png" \
  -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 24 -row-mt 1 -deadline good -cpu-used 2 \
  -auto-alt-ref 0 "$OUT.webm"
echo "wrote $OUT.webm ($(du -h "$OUT.webm" | cut -f1))"
# Safari needs hevc with alpha; only videotoolbox (macOS) encodes it — note it if unavailable.
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_videotoolbox; then
  ffmpeg -v error -y -framerate "$FPS" -i "$DIR/f%05d.png" -c:v hevc_videotoolbox -alpha_quality 0.9 -tag:v hvc1 "$OUT.mov"
  echo "wrote $OUT.mov"
else
  echo "no hevc-alpha encoder here (needs macOS videotoolbox) — Safari falls back to silhouette"
fi
