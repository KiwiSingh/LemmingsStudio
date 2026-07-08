#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MODE="${1:-simulator}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SCHEME="${VISION_SCHEME:-LemmingsStudioVision}"
DERIVED_DATA="${VISION_DERIVED_DATA:-$ROOT/.build/DerivedData}"
ARCHIVE_PATH="${VISION_ARCHIVE_PATH:-$ROOT/.build/LemmingsStudioVision.xcarchive}"
DIST_DIR="${VISION_DIST_DIR:-$ROOT/dist}"
SIM_ZIP_NAME="${VISION_SIM_ZIP_NAME:-LemmingsStudio-visionOS-v1.0-Simulator.zip}"
IPA_NAME="${VISION_IPA_NAME:-LemmingsStudio-visionOS-v1.0.ipa}"

MODEL_CACHE_ROOT="${VISION_MODEL_CACHE_DIR:-$HOME/Library/Caches/LemmingsStudio/visionOS-Models}"
MODEL_PROFILE="${VISION_MODEL_BUNDLE_PROFILE:-minimal}"

verify_icon_sources() {
  local icon_root="$ROOT/LemmingsStudioVision/Resources/Assets.xcassets/AppIcon.imagestack"
  local layer file size
  for layer in Back Middle Front; do
    file="$icon_root/$layer.imagestacklayer/Content.imageset/$layer.png"
    [[ -f "$file" ]] || { echo "error: missing visionOS app icon layer: $file" >&2; exit 1; }
    size="$(wc -c < "$file" | tr -d '[:space:]')"
    [[ "$size" -ge 10000 ]] || {
      echo "error: visionOS app icon layer looks empty or placeholder-sized: $file ($size bytes)" >&2
      exit 1
    }
  done
  echo "[visionOS] AppIcon source stack verified (Back/Middle/Front)."
}

prepare_models() {
  VISION_MODEL_BUNDLE_PROFILE="$MODEL_PROFILE" ./prepare-visionos-models.sh
}

inject_models() {
  local app_path="$1"
  [[ "$MODEL_PROFILE" == "none" ]] && return 0
  local target="$app_path/Models"
  rm -rf "$target"
  mkdir -p "$target"

  case "$MODEL_PROFILE" in
    full) slugs=(qwen25-vl-3b-4bit qwen25-vl-7b-4bit llama32-vision-11b-4bit internvl3-2b-4bit) ;;
    default) slugs=(qwen25-vl-3b-4bit qwen25-vl-7b-4bit) ;;
    minimal) slugs=(qwen25-vl-3b-4bit) ;;
    *) echo "error: unsupported model profile: $MODEL_PROFILE" >&2; exit 2 ;;
  esac

  for slug in "${slugs[@]}"; do
    [[ -f "$MODEL_CACHE_ROOT/$slug/config.json" ]] || {
      echo "error: model cache incomplete for $slug" >&2
      exit 1
    }
    echo "[visionOS] Embedding model: $slug"
    ditto "$MODEL_CACHE_ROOT/$slug" "$target/$slug"
  done
  cp "$MODEL_CACHE_ROOT/bundle-manifest.json" "$target/bundle-manifest.json"
  echo "[visionOS] Embedded model payload:"
  du -sh "$target" || true

  for slug in "${slugs[@]}"; do
    [[ -f "$target/$slug/config.json" ]] || {
      echo "error: embedded model missing config.json: $slug" >&2
      exit 1
    }
    if ! find "$target/$slug" -maxdepth 2 -type f \( -name '*.safetensors' -o -name '*.gguf' \) -print -quit | grep -q .; then
      echo "error: embedded model has no recognized weight file: $slug" >&2
      exit 1
    fi
  done
  echo "[visionOS] Model payload verification passed (${#slugs[@]} bundled model(s))."
}

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is unavailable. Install full Xcode and select it with xcode-select." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "[visionOS] XcodeGen missing; installing with Homebrew..."
    brew install xcodegen
  else
    echo "error: xcodegen is required. Install it, then rerun this script." >&2
    exit 1
  fi
fi

verify_icon_sources
xcodegen generate

package_validation_flags=()
if [[ "${VISION_SKIP_PACKAGE_PLUGIN_VALIDATION:-1}" == "1" ]]; then
  # MLX Swift 0.31.x exposes a transitive CudaBuild build-tool plugin.
  # Xcode validates package plugins before compiling, including on Apple platforms.
  # This flag is scoped to this script and can be disabled with VISION_SKIP_PACKAGE_PLUGIN_VALIDATION=0.
  package_validation_flags+=( -skipPackagePluginValidation )
fi

if [[ "${VISION_SKIP_MACRO_VALIDATION:-1}" == "1" ]]; then
  # mlx-swift-lm 3.31.x exposes MLXHuggingFaceMacros. Headless/scripted Xcode builds
  # may stop with “must be enabled before it can be used” until the macro is trusted.
  # Keep the bypass scoped to this build invocation; opt out with VISION_SKIP_MACRO_VALIDATION=0.
  package_validation_flags+=( -skipMacroValidation )
fi

common=(
  -project LemmingsStudioVision.xcodeproj
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA"
  ${package_validation_flags[@]+"${package_validation_flags[@]}"}
)

case "$MODE" in
  simulator)
    DESTINATION="${VISION_DESTINATION:-generic/platform=visionOS Simulator}"
    echo "[visionOS] Building simulator target: $DESTINATION"
    prepare_models
    xcodebuild "${common[@]}" -destination "$DESTINATION" build
    APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-xrsimulator/LemmingsStudio.app"
    [[ -d "$APP_PATH" ]] && inject_models "$APP_PATH"
    ;;

  generic-simulator)
    echo "[visionOS] Building generic visionOS Simulator target"
    prepare_models
    xcodebuild "${common[@]}" -destination "generic/platform=visionOS Simulator" build
    APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-xrsimulator/LemmingsStudio.app"
    [[ -d "$APP_PATH" ]] && inject_models "$APP_PATH"
    ;;

  device)
    DESTINATION="${VISION_DESTINATION:-generic/platform=visionOS}"
    echo "[visionOS] Building device target: $DESTINATION"
    xcodebuild "${common[@]}" -destination "$DESTINATION" build
    ;;

  archive)
    echo "[visionOS] Archiving for generic visionOS device"
    rm -rf "$ARCHIVE_PATH"
    xcodebuild \
      -project LemmingsStudioVision.xcodeproj \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination "generic/platform=visionOS" \
      -archivePath "$ARCHIVE_PATH" \
      ${package_validation_flags[@]+"${package_validation_flags[@]}"} \
      archive
    echo "[visionOS] Archive: $ARCHIVE_PATH"
    ;;

  package-simulator)
    echo "[visionOS] Building Release simulator app and packaging ZIP"
    prepare_models
    mkdir -p "$DIST_DIR"
    xcodebuild \
      -project LemmingsStudioVision.xcodeproj \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination "generic/platform=visionOS Simulator" \
      -derivedDataPath "$DERIVED_DATA" \
      ${package_validation_flags[@]+"${package_validation_flags[@]}"} \
      build
    APP_PATH="$DERIVED_DATA/Build/Products/Release-xrsimulator/LemmingsStudio.app"
    if [[ ! -d "$APP_PATH" ]]; then
      echo "error: simulator app not found at $APP_PATH" >&2
      exit 1
    fi
    inject_models "$APP_PATH"
    rm -f "$DIST_DIR/$SIM_ZIP_NAME"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/$SIM_ZIP_NAME"
    echo "[visionOS] Simulator ZIP: $DIST_DIR/$SIM_ZIP_NAME"
    ;;

  ipa)
    echo "[visionOS] Building unsigned/resignable device app and packaging sideloadable IPA"
    prepare_models
    mkdir -p "$DIST_DIR"
    DEVICE_DERIVED="$ROOT/.build/UnsignedDeviceDerivedData"
    PAYLOAD_ROOT="$ROOT/.build/ResignableIPA"
    rm -rf "$DEVICE_DERIVED" "$PAYLOAD_ROOT"

    xcodebuild \
      -project LemmingsStudioVision.xcodeproj \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination "generic/platform=visionOS" \
      -derivedDataPath "$DEVICE_DERIVED" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY="" \
      ${package_validation_flags[@]+"${package_validation_flags[@]}"} \
      build

    APP_PATH="$DEVICE_DERIVED/Build/Products/Release-xros/LemmingsStudio.app"
    if [[ ! -d "$APP_PATH" ]]; then
      echo "error: unsigned device app not found at $APP_PATH" >&2
      exit 1
    fi

    inject_models "$APP_PATH"

    mkdir -p "$PAYLOAD_ROOT/Payload"
    ditto "$APP_PATH" "$PAYLOAD_ROOT/Payload/LemmingsStudio.app"

    # Ensure the public package does not carry stale provisioning/signature metadata.
    rm -rf "$PAYLOAD_ROOT/Payload/LemmingsStudio.app/_CodeSignature"
    rm -f "$PAYLOAD_ROOT/Payload/LemmingsStudio.app/embedded.mobileprovision"

    rm -f "$DIST_DIR/$IPA_NAME"
    (cd "$PAYLOAD_ROOT" && ditto -c -k --sequesterRsrc --keepParent Payload "$DIST_DIR/$IPA_NAME")

    echo "[visionOS] Resignable sideload IPA: $DIST_DIR/$IPA_NAME"
    echo "[visionOS] End users must sign/re-sign this IPA with their own Apple identity/provisioning workflow before installation."
    ;;

  list)
    xcodebuild -project LemmingsStudioVision.xcodeproj -list
    xcodebuild -project LemmingsStudioVision.xcodeproj -scheme "$SCHEME" -showdestinations
    ;;

  *)
    echo "usage: $0 [simulator|generic-simulator|package-simulator|device|archive|ipa|list]" >&2
    exit 2
    ;;
esac
