#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
MODE="${1:-simulator}"
export VISION_MODEL_BUNDLE_PROFILE="${VISION_MODEL_BUNDLE_PROFILE:-minimal}"
echo "[visionOS release] model bundle profile: $VISION_MODEL_BUNDLE_PROFILE"

case "$MODE" in
  simulator)
    CONFIGURATION=Release ./build-visionos.sh package-simulator
    ART="$ROOT/dist/LemmingsStudio-visionOS-v1.0-Simulator.zip"
    ;;
  hardware)
    CONFIGURATION=Release ./build-visionos.sh ipa
    ART="$ROOT/dist/LemmingsStudio-visionOS-v1.0.ipa"
    ;;
  *)
    echo 'usage: ./release-visionos.sh [simulator|hardware]' >&2
    exit 2
    ;;
esac

[[ -f "$ART" ]] || { echo "error: expected artifact missing: $ART" >&2; exit 1; }
shasum -a 256 "$ART" > "$ART.sha256"
echo "visionOS release artifact: $ART"
if [[ "$MODE" == "hardware" ]]; then
  echo "hardware IPA is resignable; end users must sign/re-sign it during sideloading"
fi
