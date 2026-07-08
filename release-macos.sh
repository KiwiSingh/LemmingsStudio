#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
DIST="$ROOT/release-dist"
mkdir -p "$DIST"

./release-audit.sh
APP_VERSION_SHORT=2.0 APP_BUILD_VERSION=2.0.0 ./build.sh

APP="$ROOT/dist/LemmingsStudio.app"
[[ -d "$APP" ]] || { echo "error: expected $APP" >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo "error: Info.plist missing" >&2; exit 1; }

if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
  [[ "$short" == '2.0' ]] || { echo "error: expected CFBundleShortVersionString 2.0, got $short" >&2; exit 1; }
  [[ "$build" == '2.0.0' ]] || { echo "error: expected CFBundleVersion 2.0.0, got $build" >&2; exit 1; }
fi

OUT="$DIST/LemmingsStudio-macOS-v2.0.zip"
rm -f "$OUT"
if command -v ditto >/dev/null 2>&1; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
else
  (cd "$ROOT/dist" && zip -qry "$OUT" LemmingsStudio.app)
fi

if command -v codesign >/dev/null 2>&1; then
  codesign -dv --verbose=4 "$APP" 2>"$DIST/LemmingsStudio-macOS-v2.0-codesign.txt" || true
fi
shasum -a 256 "$OUT" > "$OUT.sha256"
echo "macOS release artifact: $OUT"
