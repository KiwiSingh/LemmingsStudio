#!/usr/bin/env bash
set -euo pipefail
APP_BUNDLE="${1:-dist/LemmingsStudio.app}"
CARLA_APP="${CARLA_APP:-}"
CARLA_BIN="${CARLA_BIN:-}"
AUTO_INSTALL_CARLA="${AUTO_INSTALL_CARLA:-1}"
CARLA_SINGLE_BIN="${CARLA_SINGLE_BIN:-}"

find_carla_app() {
  local candidate expanded
  if [[ -n "$CARLA_APP" && -d "$CARLA_APP" ]]; then
    printf '%s\n' "$CARLA_APP"
    return 0
  fi
  for candidate in \
    /Applications/Carla.app \
    /Applications/Carla2.app \
    /opt/homebrew/Caskroom/carla/*/Carla.app \
    /usr/local/Caskroom/carla/*/Carla.app \
    /opt/homebrew/Cellar/carla/*/Carla.app \
    /usr/local/Cellar/carla/*/Carla.app
  do
    for expanded in $candidate; do
      [[ -d "$expanded" ]] && { printf '%s\n' "$expanded"; return 0; }
    done
  done
  return 1
}

find_carla_bin() {
  local candidate expanded
  if [[ -n "$CARLA_BIN" && -x "$CARLA_BIN" ]]; then
    printf '%s\n' "$CARLA_BIN"
    return 0
  fi
  if command -v carla >/dev/null 2>&1; then
    command -v carla
    return 0
  fi
  for candidate in \
    /opt/homebrew/bin/carla \
    /usr/local/bin/carla \
    /opt/homebrew/Cellar/carla/*/bin/carla \
    /usr/local/Cellar/carla/*/bin/carla
  do
    for expanded in $candidate; do
      [[ -x "$expanded" ]] && { printf '%s\n' "$expanded"; return 0; }
    done
  done
  return 1
}

find_carla_single_bin() {
  local candidate expanded dir
  if [[ -n "$CARLA_SINGLE_BIN" && -x "$CARLA_SINGLE_BIN" ]]; then
    printf '%s\n' "$CARLA_SINGLE_BIN"
    return 0
  fi
  if command -v carla-single >/dev/null 2>&1; then
    command -v carla-single
    return 0
  fi
  if [[ -n "${FOUND_BIN:-}" ]]; then
    dir="$(dirname "$FOUND_BIN")"
    [[ -x "$dir/carla-single" ]] && { printf '%s\n' "$dir/carla-single"; return 0; }
  fi
  for candidate in \
    /opt/homebrew/bin/carla-single \
    /usr/local/bin/carla-single \
    /opt/homebrew/Cellar/carla/*/bin/carla-single \
    /usr/local/Cellar/carla/*/bin/carla-single
  do
    for expanded in $candidate; do
      [[ -x "$expanded" ]] && { printf '%s\n' "$expanded"; return 0; }
    done
  done
  return 1
}

install_carla_if_allowed() {
  [[ "$AUTO_INSTALL_CARLA" != "0" ]] || return 1
  command -v brew >/dev/null 2>&1 || return 1
  echo "Carla not found; attempting Homebrew install..."
  brew install --cask carla || brew install carla
}

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "LemmingsStudio app bundle not found: $APP_BUNDLE" >&2
  exit 2
fi

FOUND_CARLA="$(find_carla_app 2>/dev/null || true)"
FOUND_BIN="$(find_carla_bin 2>/dev/null || true)"
if [[ -z "$FOUND_CARLA" && -z "$FOUND_BIN" ]]; then
  install_carla_if_allowed || {
    echo "Carla not found. Install Carla first, set CARLA_APP=/path/to/Carla.app, or set CARLA_BIN=/path/to/carla" >&2
    exit 3
  }
  FOUND_CARLA="$(find_carla_app 2>/dev/null || true)"
  FOUND_BIN="$(find_carla_bin 2>/dev/null || true)"
fi

HELPERS="$APP_BUNDLE/Contents/Resources/Helpers"
mkdir -p "$HELPERS"

if [[ -n "$FOUND_CARLA" && -d "$FOUND_CARLA" ]]; then
  rm -rf "$HELPERS/Carla.app" "$HELPERS/CarlaFormula"
  ditto --norsrc "$FOUND_CARLA" "$HELPERS/Carla.app"
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$HELPERS/Carla.app" >/dev/null 2>&1 || true
  fi
  echo "Bundled Carla.app from $FOUND_CARLA into $HELPERS/Carla.app"
else
  [[ -n "$FOUND_BIN" && -x "$FOUND_BIN" ]] || { echo "Carla executable not found after install attempt." >&2; exit 4; }
  rm -rf "$HELPERS/Carla.app"
  mkdir -p "$HELPERS/CarlaFormula"
  cat > "$HELPERS/CarlaFormula/carla" <<SH
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
if [[ -x "$FOUND_BIN" ]]; then
  exec "$FOUND_BIN" "\$@"
fi
if command -v carla >/dev/null 2>&1; then
  exec carla "\$@"
fi
exit 127
SH
  chmod +x "$HELPERS/CarlaFormula/carla"
  FOUND_SINGLE="$(find_carla_single_bin 2>/dev/null || true)"
  if [[ -n "$FOUND_SINGLE" && -x "$FOUND_SINGLE" ]]; then
    cat > "$HELPERS/CarlaFormula/carla-single" <<SH
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
if [[ -x "$FOUND_SINGLE" ]]; then
  exec "$FOUND_SINGLE" "\$@"
fi
if command -v carla-single >/dev/null 2>&1; then
  exec carla-single "\$@"
fi
exit 127
SH
    chmod +x "$HELPERS/CarlaFormula/carla-single"
    echo "Bundled Carla single-plugin launcher for $FOUND_SINGLE into $HELPERS/CarlaFormula/carla-single"
  fi
  echo "Bundled Carla CLI launcher for $FOUND_BIN into $HELPERS/CarlaFormula/carla"
fi

cat > "$HELPERS/CARLA_LICENSE_NOTE.txt" <<'TXT'
Carla is GPL-2.0-or-later. If this binary is distributed inside LemmingsStudio,
ship Carla's license and corresponding source offer/source link as required by
the GPL. For closed/internal beta builds, you may prefer EMBED_CARLA=0 and rely
on the user's existing Carla install instead.
TXT
