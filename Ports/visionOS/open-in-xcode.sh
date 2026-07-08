#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

PROFILE="${VISION_MODEL_BUNDLE_PROFILE:-minimal}"
CACHE_ROOT="${VISION_MODEL_CACHE_DIR:-$HOME/Library/Caches/LemmingsStudio/visionOS-Models}"

VISION_MODEL_BUNDLE_PROFILE="$PROFILE" \
VISION_MODEL_CACHE_DIR="$CACHE_ROOT" \
./prepare-visionos-models.sh

xcodegen generate

XCODE_APP="${VISION_XCODE_APP:-/Volumes/Zweidrive/Applications/Xcode-beta.app}"
if [[ -d "$XCODE_APP" ]]; then
  open -a "$XCODE_APP" LemmingsStudioVision.xcodeproj
else
  open LemmingsStudioVision.xcodeproj
fi

cat <<MSG
[visionOS Xcode] Project opened.
[visionOS Xcode] Select an Apple Vision Pro simulator and press Command-R.
[visionOS Xcode] The post-build model staging phase uses profile: $PROFILE
MSG
