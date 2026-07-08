#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${VISION_MODEL_BUNDLE_PROFILE:-minimal}"
CACHE_ROOT="${VISION_MODEL_CACHE_DIR:-$HOME/Library/Caches/LemmingsStudio/visionOS-Models}"
VENV="${VISION_MODEL_VENV:-$ROOT/.build/model-fetch-venv}"

mkdir -p "$CACHE_ROOT" "$ROOT/.build"

case "$PROFILE" in
  full)
    MODELS=(
      "qwen25-vl-3b-4bit|mlx-community/Qwen2.5-VL-3B-Instruct-4bit"
      "qwen25-vl-7b-4bit|mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
      "llama32-vision-11b-4bit|mlx-community/Llama-3.2-11B-Vision-Instruct-4bit"
      "internvl3-2b-4bit|mlx-community/InternVL3-2B-4bit"
    )
    ;;
  default)
    MODELS=(
      "qwen25-vl-3b-4bit|mlx-community/Qwen2.5-VL-3B-Instruct-4bit"
      "qwen25-vl-7b-4bit|mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
    )
    ;;
  minimal)
    MODELS=(
      "qwen25-vl-3b-4bit|mlx-community/Qwen2.5-VL-3B-Instruct-4bit"
    )
    ;;
  none)
    echo "[visionOS models] profile=none; skipping model prefetch"
    exit 0
    ;;
  *)
    echo "error: unsupported VISION_MODEL_BUNDLE_PROFILE=$PROFILE (full|default|minimal|none)" >&2
    exit 2
    ;;
esac

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "[visionOS models] creating downloader venv: $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/python" -m pip install --upgrade pip
  "$VENV/bin/python" -m pip install 'huggingface_hub>=0.30,<2'
fi

export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-0}"

for item in "${MODELS[@]}"; do
  slug="${item%%|*}"
  repo="${item#*|}"
  dest="$CACHE_ROOT/$slug"
  echo "[visionOS models] ensuring $repo -> $dest"
  "$VENV/bin/python" - "$repo" "$dest" <<'PY'
import sys
from pathlib import Path
from huggingface_hub import snapshot_download

repo, dest = sys.argv[1], Path(sys.argv[2])
dest.mkdir(parents=True, exist_ok=True)
snapshot_download(
    repo_id=repo,
    local_dir=str(dest),
    local_dir_use_symlinks=False,
)
PY

  [[ -f "$dest/config.json" ]] || {
    echo "error: downloaded model is missing config.json: $dest" >&2
    exit 1
  }
done

cat > "$CACHE_ROOT/bundle-manifest.json" <<EOF_MANIFEST
{
  "profile": "$PROFILE",
  "models": [
$(printf '    "%s"\n' "${MODELS[@]%%|*}" | sed '$!s/$/,/')
  ]
}
EOF_MANIFEST

echo "[visionOS models] ready: $CACHE_ROOT"
du -sh "$CACHE_ROOT" || true
