#!/usr/bin/env bash
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROFILE="${VISION_MODEL_BUNDLE_PROFILE:-minimal}"
CACHE_ROOT="${VISION_MODEL_CACHE_DIR:-$HOME/Library/Caches/LemmingsStudio/visionOS-Models}"
APP_PATH="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${WRAPPER_NAME:?WRAPPER_NAME is required}"

if [[ "$PROFILE" == "none" ]]; then
  echo "[visionOS Xcode models] profile=none; leaving app bundle model-free"
  exit 0
fi

case "$PROFILE" in
  full) slugs=(qwen25-vl-3b-4bit qwen25-vl-7b-4bit llama32-vision-11b-4bit internvl3-2b-4bit) ;;
  default) slugs=(qwen25-vl-3b-4bit qwen25-vl-7b-4bit) ;;
  minimal) slugs=(qwen25-vl-3b-4bit) ;;
  *) echo "error: unsupported VISION_MODEL_BUNDLE_PROFILE=$PROFILE (full|default|minimal|none)" >&2; exit 2 ;;
esac

missing=0
for slug in "${slugs[@]}"; do
  [[ -f "$CACHE_ROOT/$slug/config.json" ]] || missing=1
done

if [[ "$missing" == "1" ]]; then
  echo "[visionOS Xcode models] cache incomplete; preparing profile=$PROFILE"
  VISION_MODEL_BUNDLE_PROFILE="$PROFILE" \
  VISION_MODEL_CACHE_DIR="$CACHE_ROOT" \
  "$ROOT/prepare-visionos-models.sh"
fi

TARGET_MODELS="$APP_PATH/Models"
rm -rf "$TARGET_MODELS"
mkdir -p "$TARGET_MODELS"

for slug in "${slugs[@]}"; do
  echo "[visionOS Xcode models] embedding $slug"
  ditto "$CACHE_ROOT/$slug" "$TARGET_MODELS/$slug"
  [[ -f "$TARGET_MODELS/$slug/config.json" ]] || {
    echo "error: staged model missing config.json: $slug" >&2
    exit 1
  }
done

if [[ -f "$CACHE_ROOT/bundle-manifest.json" ]]; then
  cp "$CACHE_ROOT/bundle-manifest.json" "$TARGET_MODELS/bundle-manifest.json"
fi

echo "[visionOS Xcode models] embedded ${#slugs[@]} model(s) into $APP_PATH"
du -sh "$TARGET_MODELS" || true
