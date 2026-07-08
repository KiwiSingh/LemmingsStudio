#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
PLIST="$APP_PATH/Info.plist"
ASSETS="$APP_PATH/Assets.car"

[[ -d "$APP_PATH" ]] || { echo "error: built app bundle missing: $APP_PATH" >&2; exit 1; }
[[ -f "$PLIST" ]] || { echo "error: built Info.plist missing: $PLIST" >&2; exit 1; }
[[ -f "$ASSETS" ]] || { echo "error: compiled asset catalog missing: $ASSETS" >&2; exit 1; }

ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon' "$PLIST" 2>/dev/null || true)"
if [[ "$ICON_NAME" != "AppIcon" ]]; then
  echo "error: built app does not declare AppIcon as CFBundlePrimaryIcon (found: ${ICON_NAME:-<missing>})" >&2
  exit 1
fi

echo "[visionOS] Built AppIcon verification passed: metadata=AppIcon, Assets.car present."
