#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/Sources/LemmingsStudio/Resources"
SRC="$RES/MagmaVancePreSplash.mp4"
if [[ ! -f "$SRC" ]]; then
  echo "MagmaVance pre-splash source not found: $SRC" >&2
  exit 0
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found; keeping existing pre-splash variants and relying on 60 fps fallback." >&2
  exit 0
fi
for fps in 60 75 90 120 144 165 240; do
  out="$RES/MagmaVancePreSplash_${fps}.mp4"
  if [[ -f "$out" ]]; then
    continue
  fi
  echo "Generating MagmaVance pre-splash ${fps} fps → $out"
  ffmpeg -y -i "$SRC" -vf "fps=${fps}" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart -an "$out"
done
