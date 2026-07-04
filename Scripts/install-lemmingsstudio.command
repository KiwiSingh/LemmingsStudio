#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_NAME="LemmingsStudio.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SCRIPT_DIR/$APP_BUNDLE_NAME"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Could not find $APP_BUNDLE_NAME next to this installer."
  echo "Expected: $SOURCE_APP"
  read -r -p "Press Return to exit. " _
  exit 1
fi

echo "LemmingsStudio installer"
echo "========================"
echo

echo "Where should LemmingsStudio be installed?"
echo "  1) Internal SSD: /Applications"
echo "  2) External drive: /Volumes/<Drive>/Applications"
echo
read -r -p "Choose 1 or 2 [1]: " choice
choice="${choice:-1}"

DEST_DIR=""
case "$choice" in
  1)
    DEST_DIR="/Applications"
    ;;
  2)
    echo
    echo "Mounted external volumes:"
    find /Volumes -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sed 's#^/Volumes/##' | sort | sed 's/^/  - /'
    echo
    read -r -p "Enter external drive name or full /Volumes path: " volume_choice
    if [[ -z "$volume_choice" ]]; then
      echo "No external drive specified."
      exit 1
    fi
    if [[ "$volume_choice" == /Volumes/* ]]; then
      VOLUME_PATH="$volume_choice"
    else
      VOLUME_PATH="/Volumes/$volume_choice"
    fi
    if [[ ! -d "$VOLUME_PATH" ]]; then
      echo "External drive not found: $VOLUME_PATH"
      exit 1
    fi
    DEST_DIR="$VOLUME_PATH/Applications"
    if [[ ! -d "$DEST_DIR" ]]; then
      echo "Creating $DEST_DIR"
      mkdir -p "$DEST_DIR" 2>/dev/null || sudo mkdir -p "$DEST_DIR"
    fi
    ;;
  *)
    echo "Invalid choice: $choice"
    exit 1
    ;;
esac

DEST_APP="$DEST_DIR/$APP_BUNDLE_NAME"
echo
echo "Installing to: $DEST_APP"

if [[ -d "$DEST_APP" ]]; then
  read -r -p "Replace existing LemmingsStudio.app? [y/N]: " replace
  case "$replace" in
    y|Y|yes|YES)
      rm -rf "$DEST_APP" 2>/dev/null || sudo rm -rf "$DEST_APP"
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
fi

# A mounted release DMG is normally read-only, so a true mv is not always possible.
# Try mv for writable source folders; fall back to ditto/copy for DMG installs.
if mv "$SOURCE_APP" "$DEST_APP" 2>/dev/null; then
  echo "Moved app bundle."
else
  echo "Source appears read-only; copying app bundle from installer image."
  /usr/bin/ditto "$SOURCE_APP" "$DEST_APP" 2>/dev/null || sudo /usr/bin/ditto "$SOURCE_APP" "$DEST_APP"
fi

echo
echo "Blessing/trusting the installed app bundle. macOS may ask for your password."
# Avoid changing the app's signature. This only removes quarantine and adds a local Gatekeeper allow-label.
sudo /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
sudo /usr/sbin/spctl --add --label "LemmingsStudio" "$DEST_APP" 2>/dev/null || true
sudo /usr/sbin/spctl --enable --label "LemmingsStudio" 2>/dev/null || true

# Make sure the installed bundle is readable/executable from an external Applications folder.
sudo /bin/chmod -R a+rX "$DEST_APP" 2>/dev/null || true

echo
echo "Gatekeeper status:"
/usr/sbin/spctl -a -vv "$DEST_APP" 2>&1 || true

echo
echo "✓ Installed LemmingsStudio at: $DEST_APP"
read -r -p "Open LemmingsStudio now? [Y/n]: " open_now
open_now="${open_now:-Y}"
case "$open_now" in
  n|N|no|NO) ;;
  *) open "$DEST_APP" ;;
esac
