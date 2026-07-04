#!/usr/bin/env bash
# build.sh — build LemmingsStudio and package it as a real, mostly self-contained macOS .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LemmingsStudio"
DISPLAY_NAME="Lemmings Studio"
BUNDLE_ID="com.magmavance.LemmingsStudio"
APP_VERSION_SHORT="${APP_VERSION_SHORT:-1.1}"
APP_BUILD_VERSION="${APP_BUILD_VERSION:-1.1.0}"
CONFIG="Release"
if [[ "${1:-}" == "debug" || "${1:-}" == "Debug" ]]; then
  CONFIG="Debug"
fi

# Set EMBED_PYTHON=0 to skip Python bundling.
# Set EMBED_DEMUCS=0 to skip creating the bundled Demucs virtualenv.
# Set PYTHON_BIN=/path/to/python3 to choose the Python runtime that gets embedded.
# Set DEMUCS_PIP_SPEC="demucs" to override the official PyTorch Demucs package spec.
# Set EMBED_DEMUCS_MLX=0 to skip bundling the Apple Silicon MLX Demucs backend.
# Set DEMUCS_MLX_PIP_SPEC="demucs-mlx" to override the MLX package spec.
# Set DEMUCS_MLX_CONVERT_PIP_SPEC="demucs-mlx[convert]" to override the conversion/preload package spec.
# Set DEMUCS_MLX_PRELOAD_WEIGHTS=0 to skip downloading/pre-converting MLX model weights.
# Set DEMUCS_MLX_PRELOAD_MODELS="htdemucs htdemucs_ft htdemucs_6s" to choose bundled MLX weights.
# Set DEMUCS_PRELOAD_WEIGHTS=0 to skip pre-caching official PyTorch Demucs weights.
# Set DEMUCS_PRELOAD_MODELS="htdemucs htdemucs_ft htdemucs_6s" to choose official Demucs weights.
# Set DEMUCS_PRELOAD_STRICT=1 to fail packaging if official Demucs weights cannot be cached.
# Set DEMUCS_MLX_ALLOW_INSECURE_SSL=1 only as a last-resort packaging fallback if Python certs are broken.
# Set DEMUCS_MLX_PRELOAD_STRICT=1 to fail packaging if requested MLX weights are not actually present.
# Set DEMUCS_MLX_HF_REPO=mlx-community/demucs-mlx to override the preconverted MLX weight repo.
# Set EMBED_RVC=0 to skip bundled voice-conversion dependencies.
# RVC packaging is intentionally full-fat: runtime repo + HuBERT/RMVPE/pretrained assets are bundled when available.
# Set RVC_RUNTIME_REPO / RVC_RUNTIME_REF to pin a fork or commit.
# Set RVC_ASSETS_HF_REPO to override the Hugging Face asset repository.
# Set RVC_PRELOAD_STRICT=1 to fail packaging if requested RVC assets are missing.
# Set RVC_PRELOAD_ALL=1 to pull every known RVC asset folder from the Hugging Face repo; this can be huge.
# Set RVC_TRY_FAIRSEQ=1 to attempt legacy fairseq install; disabled by default because it is fragile on new Python/macOS.
# Set RVC_INSTALL_PYPI_ADAPTERS=1 to attempt optional rvc-python/rvc-inferpy adapters; disabled by default on modern Python.
# Set RVC_ALLOW_LEGACY_NUMBA=1 to attempt old numba/llvmlite pins on Python >=3.12; disabled by default.
# Set EMBED_CARLA=0 to skip bundling Carla.
# Set AUTO_INSTALL_CARLA=0 to avoid Homebrew installs during packaging.
# Set CARLA_APP=/path/to/Carla.app to use a specific Carla build.
EMBED_PYTHON="${EMBED_PYTHON:-1}"
EMBED_DEMUCS="${EMBED_DEMUCS:-1}"
EMBED_RVC="${EMBED_RVC:-1}"
EMBED_CARLA="${EMBED_CARLA:-1}"
AUTO_INSTALL_CARLA="${AUTO_INSTALL_CARLA:-1}"
CARLA_APP="${CARLA_APP:-}"
PYTHON_BIN="${PYTHON_BIN:-}"
DEMUCS_PIP_SPEC="${DEMUCS_PIP_SPEC:-demucs soundfile}"
DEMUCS_PRELOAD_WEIGHTS="${DEMUCS_PRELOAD_WEIGHTS:-1}"
DEMUCS_PRELOAD_MODELS="${DEMUCS_PRELOAD_MODELS:-htdemucs htdemucs_ft htdemucs_6s}"
DEMUCS_PRELOAD_STRICT="${DEMUCS_PRELOAD_STRICT:-0}"
EMBED_DEMUCS_MLX="${EMBED_DEMUCS_MLX:-auto}"
DEMUCS_MLX_PIP_SPEC="${DEMUCS_MLX_PIP_SPEC:-demucs-mlx}"
DEMUCS_MLX_CONVERT_PIP_SPEC="${DEMUCS_MLX_CONVERT_PIP_SPEC:-demucs-mlx[convert]}"
DEMUCS_MLX_PRELOAD_WEIGHTS="${DEMUCS_MLX_PRELOAD_WEIGHTS:-auto}"
DEMUCS_MLX_PRELOAD_MODELS="${DEMUCS_MLX_PRELOAD_MODELS:-htdemucs htdemucs_ft htdemucs_6s}"
DEMUCS_MLX_ALLOW_INSECURE_SSL="${DEMUCS_MLX_ALLOW_INSECURE_SSL:-0}"
DEMUCS_MLX_PRELOAD_STRICT="${DEMUCS_MLX_PRELOAD_STRICT:-0}"
DEMUCS_MLX_HF_REPO="${DEMUCS_MLX_HF_REPO:-mlx-community/demucs-mlx}"
RVC_PIP_SPEC="${RVC_PIP_SPEC:-torch torchaudio numpy scipy librosa soundfile praat-parselmouth pyworld ffmpeg-python av pydub tqdm requests numba scikit-learn resampy einops joblib tensorboardX gradio==3.34.0 huggingface_hub}"
# Fairseq is intentionally not installed by default. RVC forks/assets can still be
# bundled full-fat without letting fairseq's legacy setup.py break packaging.
# Opt in only when building with a known-compatible Python, e.g. 3.10/3.11.
RVC_TRY_FAIRSEQ="${RVC_TRY_FAIRSEQ:-0}"
RVC_INSTALL_PYPI_ADAPTERS="${RVC_INSTALL_PYPI_ADAPTERS:-0}"
RVC_ALLOW_LEGACY_NUMBA="${RVC_ALLOW_LEGACY_NUMBA:-0}"
RVC_ADAPTER_PIP_SPEC="${RVC_ADAPTER_PIP_SPEC:-rvc-python rvc-inferpy}"
RVC_OPTIONAL_PIP_SPEC="${RVC_OPTIONAL_PIP_SPEC:-}"
if [[ "$RVC_TRY_FAIRSEQ" == "1" && -z "$RVC_OPTIONAL_PIP_SPEC" ]]; then
  RVC_OPTIONAL_PIP_SPEC="fairseq"
fi
if [[ "$RVC_INSTALL_PYPI_ADAPTERS" == "1" ]]; then
  RVC_OPTIONAL_PIP_SPEC="$RVC_OPTIONAL_PIP_SPEC $RVC_ADAPTER_PIP_SPEC"
fi
RVC_RUNTIME_REPO="${RVC_RUNTIME_REPO:-https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI.git}"
RVC_RUNTIME_REF="${RVC_RUNTIME_REF:-main}"
RVC_ASSETS_HF_REPO="${RVC_ASSETS_HF_REPO:-lj1995/VoiceConversionWebUI}"
RVC_PRELOAD_STRICT="${RVC_PRELOAD_STRICT:-0}"
RVC_PRELOAD_ALL="${RVC_PRELOAD_ALL:-0}"
RVC_ALLOW_PATTERNS="${RVC_ALLOW_PATTERNS:-hubert_base.pt rmvpe.pt rmvpe.onnx pretrained/* pretrained_v2/* pretrained_v0/* uvr5_weights/* infer_pack/*}"
AUTO_INSTALL_OLLAMA="${AUTO_INSTALL_OLLAMA:-0}"

DERIVED_DATA=".build/xcode"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIG"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
BUILD_LOG=".build/${APP_NAME}-${CONFIG}.log"

lower_config() { printf '%s' "$CONFIG" | tr '[:upper:]' '[:lower:]'; }

find_built_binary() {
  local candidate="$PRODUCTS_DIR/$APP_NAME"
  if [[ -x "$candidate" && ! -d "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  find "$DERIVED_DATA/Build/Products" -type f -name "$APP_NAME" -perm -111 -print 2>/dev/null | head -n 1
}

copy_item() {
  local src="$1"
  local dst_dir="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$dst_dir"
  ditto "$src" "$dst_dir/$(basename "$src")"
}

is_system_lib() {
  case "$1" in
    /System/*|/usr/lib/*) return 0 ;;
    *) return 1 ;;
  esac
}

copy_absolute_macho_deps() {
  # Best-effort dependency bundling for non-system dylibs/frameworks next to the app executable.
  # System frameworks remain dynamically linked to macOS; Homebrew/local libs are copied in.
  command -v otool >/dev/null 2>&1 || return 0
  command -v install_name_tool >/dev/null 2>&1 || true

  local root_binary="$1"
  local queue_file=".build/deps-to-scan.txt"
  local seen_file=".build/deps-seen.txt"
  : > "$queue_file"
  : > "$seen_file"
  printf '%s\n' "$root_binary" >> "$queue_file"

  while IFS= read -r macho; do
    [[ -f "$macho" ]] || continue
    grep -qxF "$macho" "$seen_file" 2>/dev/null && continue
    printf '%s\n' "$macho" >> "$seen_file"

    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      [[ "$dep" == @* ]] && continue
      is_system_lib "$dep" && continue
      [[ -e "$dep" ]] || continue

      if [[ "$dep" == *.framework/* ]]; then
        local framework_root="${dep%%.framework/*}.framework"
        local framework_name="$(basename "$framework_root")"
        if [[ ! -d "$FRAMEWORKS_DIR/$framework_name" ]]; then
          echo "  • Embedding linked framework: $framework_name"
          ditto "$framework_root" "$FRAMEWORKS_DIR/$framework_name"
          find "$FRAMEWORKS_DIR/$framework_name" -type f -perm -111 -print >> "$queue_file" 2>/dev/null || true
        fi
        if command -v install_name_tool >/dev/null 2>&1; then
          install_name_tool -change "$dep" "@executable_path/../Frameworks/$framework_name/${dep##*.framework/}" "$macho" 2>/dev/null || true
        fi
      elif [[ "$dep" == *.dylib ]]; then
        local lib_name="$(basename "$dep")"
        if [[ ! -f "$FRAMEWORKS_DIR/$lib_name" ]]; then
          echo "  • Embedding linked dylib: $lib_name"
          ditto "$dep" "$FRAMEWORKS_DIR/$lib_name"
          chmod +w "$FRAMEWORKS_DIR/$lib_name" 2>/dev/null || true
          printf '%s\n' "$FRAMEWORKS_DIR/$lib_name" >> "$queue_file"
        fi
        if command -v install_name_tool >/dev/null 2>&1; then
          install_name_tool -change "$dep" "@executable_path/../Frameworks/$lib_name" "$macho" 2>/dev/null || true
          install_name_tool -id "@executable_path/../Frameworks/$lib_name" "$FRAMEWORKS_DIR/$lib_name" 2>/dev/null || true
        fi
      fi
    done < <(otool -L "$macho" 2>/dev/null | tail -n +2 | awk '{print $1}')
  done < "$queue_file"
}

find_python_bin() {
  if [[ -n "$PYTHON_BIN" && -x "$PYTHON_BIN" ]]; then
    printf '%s\n' "$PYTHON_BIN"
    return 0
  fi
  for candidate in \
    /Library/Frameworks/Python.framework/Versions/Current/bin/python3 \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    /usr/bin/python3
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  command -v python3 2>/dev/null || true
}

embed_python_runtime() {
  [[ "$EMBED_PYTHON" != "0" ]] || { echo "  • Python embedding disabled (EMBED_PYTHON=0)"; return 0; }
  local py
  py="$(find_python_bin)"
  if [[ -z "$py" || ! -x "$py" ]]; then
    echo "  ⚠️  No python3 found; skipping bundled Python runtime."
    return 0
  fi

  local py_info
  py_info="$($py - <<'PY'
import json, os, sys, sysconfig
print(json.dumps({
    "executable": sys.executable,
    "prefix": sys.prefix,
    "base_prefix": getattr(sys, "base_prefix", sys.prefix),
    "version": f"{sys.version_info.major}.{sys.version_info.minor}",
    "stdlib": sysconfig.get_path("stdlib"),
    "platstdlib": sysconfig.get_path("platstdlib"),
    "purelib": sysconfig.get_path("purelib"),
    "platlib": sysconfig.get_path("platlib"),
    "is_framework": "Python.framework" in sys.executable or "Python.framework" in sys.prefix,
}))
PY
)"

  local exe prefix base_prefix version is_framework
  exe="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["executable"])' <<<"$py_info")"
  prefix="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["prefix"])' <<<"$py_info")"
  base_prefix="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["base_prefix"])' <<<"$py_info")"
  version="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])' <<<"$py_info")"
  is_framework="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["is_framework"])' <<<"$py_info")"

  echo "  • Embedding Python $version from $exe"

  # Preferred path for python.org framework builds: copy the entire framework into Contents/Frameworks.
  if [[ "$is_framework" == "True" && "$exe" == *Python.framework* ]]; then
    local framework_root="${exe%%Python.framework/*}Python.framework"
    if [[ -d "$framework_root" ]]; then
      echo "  • Copying Python.framework (this can be large)"
      ditto --norsrc "$framework_root" "$FRAMEWORKS_DIR/Python.framework"
      find "$FRAMEWORKS_DIR/Python.framework" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
      find "$FRAMEWORKS_DIR/Python.framework" \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
      local bundled_fw_py="$FRAMEWORKS_DIR/Python.framework/Versions/$version/bin/python3"
      [[ -x "$bundled_fw_py" ]] || bundled_fw_py="$FRAMEWORKS_DIR/Python.framework/Versions/Current/bin/python3"
      if [[ -x "$bundled_fw_py" ]]; then
        printf '%s\n' "@executable_path/../Frameworks/Python.framework/Versions/$version/bin/python3" > "$RESOURCES_DIR/bundled-python-path.txt"
      fi
      return 0
    fi
  fi

  # Generic fallback: copy the base Python prefix into Resources/Python.
  # This catches Homebrew and pyenv-ish installs. It is best-effort because some Python builds
  # have absolute install names; the app still falls back to system python if the embedded copy fails.
  local py_dst="$RESOURCES_DIR/Python"
  echo "  • Copying Python prefix: $base_prefix -> $py_dst"
  rm -rf "$py_dst"
  ditto --norsrc "$base_prefix" "$py_dst"
  find "$py_dst" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
  find "$py_dst" \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true

  local bundled_py="$py_dst/bin/python3"
  if [[ -x "$bundled_py" ]]; then
    printf '%s\n' "@executable_path/../Resources/Python/bin/$(basename "$bundled_py")" > "$RESOURCES_DIR/bundled-python-path.txt"
  fi
}

resolve_bundle_python() {
  local marker="$RESOURCES_DIR/bundled-python-path.txt"
  if [[ -f "$marker" ]]; then
    local raw
    raw="$(tr -d '\r' < "$marker" | head -n 1)"
    if [[ "$raw" == @executable_path* ]]; then
      raw="${raw/@executable_path/$MACOS_DIR}"
    fi
    if [[ -x "$raw" ]]; then
      printf '%s\n' "$raw"
      return 0
    fi
  fi

  for candidate in \
    "$FRAMEWORKS_DIR/Python.framework/Versions/Current/bin/python3" \
    "$FRAMEWORKS_DIR/Python.framework/Versions"/*/bin/python3 \
    "$RESOURCES_DIR/Python/bin/python3"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

install_demucs_venv() {
  [[ "$EMBED_PYTHON" != "0" ]] || return 0
  [[ "$EMBED_DEMUCS" != "0" ]] || { echo "  • Demucs embedding disabled (EMBED_DEMUCS=0)"; return 0; }

  local py
  if ! py="$(resolve_bundle_python)"; then
    echo "  ⚠️  Bundled Python was not found; cannot create bundled Demucs venv."
    return 0
  fi

  local venv_dir="$RESOURCES_DIR/PythonVenv"
  echo "  • Creating bundled Demucs venv with: $py"
  rm -rf "$venv_dir"

  if ! "$py" -m venv "$venv_dir"; then
    echo "  ⚠️  venv creation failed; trying ensurepip and retrying"
    "$py" -m ensurepip --upgrade || true
    "$py" -m venv "$venv_dir"
  fi

  local venv_py="$venv_dir/bin/python3"
  if [[ ! -x "$venv_py" ]]; then
    echo "  ⚠️  Created venv but could not find python3; skipping Demucs install."
    return 0
  fi

  echo "  • Installing/updating pip tooling inside bundled python3 venv"
  "$venv_py" -m ensurepip --upgrade || true
  "$venv_py" -m pip install --upgrade pip setuptools wheel || \
    "$venv_py" -m pip install --upgrade pip setuptools wheel --break-system-packages || true

  echo "  • Installing Demucs into bundled venv: $DEMUCS_PIP_SPEC"
  # shellcheck disable=SC2086  # intentional word-splitting: spec may list multiple packages
  if ! "$venv_py" -m pip install $DEMUCS_PIP_SPEC; then
    echo "  • Retrying Demucs install with --break-system-packages"
    # shellcheck disable=SC2086
    "$venv_py" -m pip install $DEMUCS_PIP_SPEC --break-system-packages
  fi

  echo "  • Installing certifi for official Demucs runtime downloads"
  "$venv_py" -m pip install certifi >/dev/null 2>&1 || "$venv_py" -m pip install certifi --break-system-packages >/dev/null 2>&1 || true

  echo "  • Verifying bundled Demucs import"
  "$venv_py" - <<'PY'
import demucs, sys
print("Demucs import OK:", getattr(demucs, "__version__", "unknown"), "via", sys.executable)
PY

  if [[ "$DEMUCS_PRELOAD_WEIGHTS" != "0" ]]; then
    local demucs_cache_root="$RESOURCES_DIR/StemBackends/ModelCache"
    local torch_home="$demucs_cache_root/torch"
    mkdir -p "$torch_home/hub/checkpoints"
    echo "  • Pre-caching official Demucs model weights into app bundle cache: $DEMUCS_PRELOAD_MODELS"
    if ! PATH="$venv_dir/bin:$PATH" TORCH_HOME="$torch_home" XDG_CACHE_HOME="$demucs_cache_root" DEMUCS_PRELOAD_MODELS="$DEMUCS_PRELOAD_MODELS" "$venv_py" - <<'PYDEMUCSCACHE'
import os, ssl, sys
try:
    import certifi
    cafile = certifi.where()
    os.environ.setdefault("SSL_CERT_FILE", cafile)
    os.environ.setdefault("REQUESTS_CA_BUNDLE", cafile)
    os.environ.setdefault("CURL_CA_BUNDLE", cafile)
except Exception as exc:
    print(f"certifi unavailable during official Demucs preload: {exc!r}", file=sys.stderr)
try:
    from demucs.pretrained import get_model
except Exception as exc:
    print(f"Could not import Demucs pretrained loader: {exc!r}", file=sys.stderr)
    sys.exit(1)
models = os.environ.get("DEMUCS_PRELOAD_MODELS", "htdemucs").split()
for model in models:
    print(f"Preloading official Demucs model: {model}")
    get_model(model)
print("Official Demucs preload complete")
PYDEMUCSCACHE
    then
      echo "      ⚠️  Official Demucs model preload failed; runtime may need network access."
      cat > "$RESOURCES_DIR/official-demucs-preload-warning.txt" <<TXT
Official Demucs was installed, but build.sh could not pre-cache one or more model weights.
Requested models: $DEMUCS_PRELOAD_MODELS

Runtime will still try to use certifi-backed HTTPS and app/user caches, but first stem split may download weights.
Set DEMUCS_PRELOAD_STRICT=1 to fail packaging instead.
TXT
      if [[ "$DEMUCS_PRELOAD_STRICT" == "1" ]]; then
        echo "      ❌ DEMUCS_PRELOAD_STRICT=1: failing packaging because official Demucs weights were not cached." >&2
        exit 1
      fi
    else
      echo "      ✓ Official Demucs weights cached under Contents/Resources/StemBackends/ModelCache/torch"
    fi
  else
    echo "  • Official Demucs weight preloading disabled (DEMUCS_PRELOAD_WEIGHTS=0)"
  fi

  # Prefer the venv for stem splitting. The venv contains Demucs/Torch; the copied Python runtime remains the base runtime.
  printf '%s\n' "@executable_path/../Resources/PythonVenv/bin/$(basename "$venv_py")" > "$RESOURCES_DIR/bundled-python-path.txt"

  # Trim caches only; keep site-packages, Torch dylibs, and metadata intact.
  find "$venv_dir" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
  find "$venv_dir" \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
}

printf '▶︎ Building %s (%s)…\n' "$DISPLAY_NAME" "$CONFIG"
mkdir -p .build "$DIST_DIR"

if command -v xcodebuild >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1; then
  echo "  • Using xcodebuild"
  set +e
  xcodebuild \
    -scheme "$APP_NAME" \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build | tee "$BUILD_LOG"
  status=${PIPESTATUS[0]}
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "✗ xcodebuild failed. Last 80 lines:"
    tail -n 80 "$BUILD_LOG" || true
    exit "$status"
  fi
  BIN="$(find_built_binary || true)"
else
  echo "  • Xcode not found — falling back to swift build"
  swift build -c "$(lower_config)"
  BIN="$(swift build -c "$(lower_config)" --show-bin-path)/$APP_NAME"
  PRODUCTS_DIR="$(dirname "$BIN")"
fi

if [[ -z "${BIN:-}" || ! -x "$BIN" ]]; then
  echo "✗ Build succeeded, but I could not find the executable under $PRODUCTS_DIR"
  exit 1
fi
printf '  • Raw executable: %s\n' "$BIN"

printf '▶︎ Packaging app bundle: %s\n' "$APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

# Main executable.
ditto "$BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# SwiftPM resource bundles from the product directory. The product directory itself
# will still contain a raw executable and .bundle; Finder will not show that as an app.
# The actual double-clickable app is dist/LemmingsStudio.app.
if [[ -d "$PRODUCTS_DIR" ]]; then
  while IFS= read -r item; do
    echo "  • Embedding resource bundle: $(basename "$item")"
    copy_item "$item" "$RESOURCES_DIR"
  done < <(find "$PRODUCTS_DIR" -maxdepth 1 \( -name '*.bundle' -o -name '*.resources' \) -print 2>/dev/null || true)

  while IFS= read -r item; do
    echo "  • Embedding product dylib: $(basename "$item")"
    copy_item "$item" "$FRAMEWORKS_DIR"
  done < <(find "$PRODUCTS_DIR" -maxdepth 1 -type f -name '*.dylib' -print 2>/dev/null || true)

  while IFS= read -r item; do
    echo "  • Embedding product framework: $(basename "$item")"
    copy_item "$item" "$FRAMEWORKS_DIR"
  done < <(find "$PRODUCTS_DIR" -maxdepth 1 -type d -name '*.framework' -print 2>/dev/null || true)
fi

# Copy startup WAVs to the app Resources root as well as the SwiftPM bundle.
# SwiftPM's .copy("Resources") keeps them nested, but AVAudioPlayer startup
# lookup should also work from the final .app without depending on bundle layout.
if [[ -d "Sources/LemmingsStudio/Resources" ]]; then
  for wav in LemmingsStartup.wav startup.wav; do
    if [[ -f "Sources/LemmingsStudio/Resources/$wav" ]]; then
      echo "  • Embedding startup sound: $wav"
      ditto "Sources/LemmingsStudio/Resources/$wav" "$RESOURCES_DIR/$wav"
    fi
  done
fi

# PackageFrameworks sometimes appears next to SwiftPM executable products.
if [[ -d "$PRODUCTS_DIR/PackageFrameworks" ]]; then
  echo "  • Embedding PackageFrameworks"
  while IFS= read -r item; do
    copy_item "$item" "$FRAMEWORKS_DIR"
  done < <(find "$PRODUCTS_DIR/PackageFrameworks" -mindepth 1 -maxdepth 1 -print 2>/dev/null || true)
fi

# Best-effort non-system dylib/framework dependency closure.
copy_absolute_macho_deps "$MACOS_DIR/$APP_NAME"


install_demucs_mlx_backend() {
  [[ "$EMBED_PYTHON" != "0" ]] || return 0
  [[ "$EMBED_DEMUCS" != "0" ]] || return 0

  local should_embed="$EMBED_DEMUCS_MLX"
  if [[ "$should_embed" == "auto" ]]; then
    if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
      should_embed="1"
    else
      should_embed="0"
    fi
  fi
  [[ "$should_embed" != "0" ]] || { echo "  • MLX Demucs embedding disabled/skipped (EMBED_DEMUCS_MLX=$EMBED_DEMUCS_MLX)"; return 0; }

  local venv_py="$RESOURCES_DIR/PythonVenv/bin/python3"
  if [[ ! -x "$venv_py" ]]; then
    echo "  ⚠️  PythonVenv/bin/python3 missing; MLX Demucs backend will not be embedded."
    return 0
  fi

  echo "  • Installing Apple Silicon MLX Demucs backend into bundled python3 venv: $DEMUCS_MLX_PIP_SPEC"
  if ! "$venv_py" -m pip install "$DEMUCS_MLX_PIP_SPEC"; then
    echo "  • Retrying MLX Demucs install with --break-system-packages"
    if ! "$venv_py" -m pip install "$DEMUCS_MLX_PIP_SPEC" --break-system-packages; then
      echo "  ⚠️  MLX Demucs install failed; official Demucs remains bundled as fallback."
      cat > "$RESOURCES_DIR/demucs-mlx-warning.txt" <<TXT
MLX Demucs was requested during packaging but failed to install.
The app bundle still includes official Demucs when that install succeeded.
Retry with: DEMUCS_MLX_PIP_SPEC=demucs-mlx ./build.sh
Or disable it with: EMBED_DEMUCS_MLX=0 ./build.sh
TXT
      return 0
    fi
  fi

  echo "  • Installing certifi + Hugging Face helpers for Demucs MLX downloads/runtime"
  if ! "$venv_py" -m pip install certifi "huggingface_hub[hf_xet]"; then
    "$venv_py" -m pip install certifi "huggingface_hub[hf_xet]" --break-system-packages || true
  fi

  echo "  • Verifying bundled MLX Demucs import"
  if ! "$venv_py" - <<'PYVERIFY'
import demucs_mlx, sys
print("Demucs MLX import OK via", sys.executable)
PYVERIFY
  then
    echo "  ⚠️  demucs_mlx import failed after install; keeping package but not creating runner wrappers."
    return 0
  fi

  local backends_dir="$RESOURCES_DIR/StemBackends"
  local mlx_cache_root="$backends_dir/ModelCache"
  mkdir -p "$backends_dir" "$mlx_cache_root"
  cat > "$backends_dir/demucs-mlx" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
RESOURCES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PY="$RESOURCES_DIR/PythonVenv/bin/python3"
CACHE_ROOT="$RESOURCES_DIR/StemBackends/ModelCache"
if [[ ! -x "$PY" ]]; then
  echo "Bundled PythonVenv was not found for demucs-mlx" >&2
  exit 127
fi
mkdir -p "$CACHE_ROOT"
# Keep Demucs MLX / Hugging Face / mlx-weights caches inside the app bundle when possible,
# so first use does not have to redownload weights to ~/.cache.
export XDG_CACHE_HOME="$CACHE_ROOT"
export HF_HOME="$CACHE_ROOT/huggingface"
export HF_HUB_CACHE="$CACHE_ROOT/huggingface/hub"
export MLX_WEIGHTS_CACHE="$CACHE_ROOT/mlx-weights"
# Python.org/macOS beta installs can miss system CAs. Prefer certifi from the
# bundled venv so urllib/requests downloads for Demucs weights verify cleanly.
CERT_FILE=$("$PY" - <<'PYCERT'
try:
    import certifi
    print(certifi.where())
except Exception:
    print("")
PYCERT
)
if [[ -n "$CERT_FILE" && -f "$CERT_FILE" ]]; then
  export SSL_CERT_FILE="$CERT_FILE"
  export REQUESTS_CA_BUNDLE="$CERT_FILE"
  export CURL_CA_BUNDLE="$CERT_FILE"
fi
exec "$PY" -m demucs_mlx "$@"
SH
  chmod +x "$backends_dir/demucs-mlx"
  cp "$backends_dir/demucs-mlx" "$backends_dir/mlx-demucs"

  local should_preload="$DEMUCS_MLX_PRELOAD_WEIGHTS"
  if [[ "$should_preload" == "auto" ]]; then
    if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
      should_preload="1"
    else
      should_preload="0"
    fi
  fi

  if [[ "$should_preload" != "0" ]]; then
    echo "  • Installing MLX Demucs conversion/preload helpers: $DEMUCS_MLX_CONVERT_PIP_SPEC"
    if ! "$venv_py" -m pip install "$DEMUCS_MLX_CONVERT_PIP_SPEC"; then
      echo "  • Retrying MLX Demucs conversion helper install with --break-system-packages"
      "$venv_py" -m pip install "$DEMUCS_MLX_CONVERT_PIP_SPEC" --break-system-packages || true
    fi
    echo "  • Ensuring certifi + Hugging Face helpers are available for Demucs MLX model downloads"
    "$venv_py" -m pip install certifi "huggingface_hub[hf_xet]" >/dev/null 2>&1 || true

    # First try the preconverted MLX weight bundle. This avoids the brittle PyTorch
    # conversion path that downloads .th files from dl.fbaipublicfiles.com during
    # packaging and can fail on Python/macOS trust-store weirdness.
    echo "  • Downloading preconverted Demucs MLX weight cache from Hugging Face: $DEMUCS_MLX_HF_REPO"
    local hf_cache_dir="$mlx_cache_root/demucs-mlx"
    mkdir -p "$hf_cache_dir"
    if ! PATH="$RESOURCES_DIR/PythonVenv/bin:$PATH" XDG_CACHE_HOME="$mlx_cache_root" HF_HOME="$mlx_cache_root/huggingface" HF_HUB_CACHE="$mlx_cache_root/huggingface/hub" MLX_WEIGHTS_CACHE="$mlx_cache_root/mlx-weights" DEMUCS_MLX_HF_REPO="$DEMUCS_MLX_HF_REPO" DEMUCS_MLX_HF_LOCAL_DIR="$hf_cache_dir" DEMUCS_MLX_ALLOW_INSECURE_SSL="$DEMUCS_MLX_ALLOW_INSECURE_SSL" "$venv_py" - <<PYHFDOWNLOAD
import os, ssl, sys
from pathlib import Path
try:
    import certifi
    cafile = certifi.where()
    os.environ.setdefault("SSL_CERT_FILE", cafile)
    os.environ.setdefault("REQUESTS_CA_BUNDLE", cafile)
    os.environ.setdefault("CURL_CA_BUNDLE", cafile)
except Exception:
    pass
if os.environ.get("DEMUCS_MLX_ALLOW_INSECURE_SSL") == "1":
    ssl._create_default_https_context = ssl._create_unverified_context
try:
    from huggingface_hub import snapshot_download
    repo = os.environ.get("DEMUCS_MLX_HF_REPO", "mlx-community/demucs-mlx")
    local_dir = os.environ["DEMUCS_MLX_HF_LOCAL_DIR"]
    print(f"Downloading {repo} -> {local_dir}")
    snapshot_download(repo_id=repo, repo_type="model", local_dir=local_dir, local_dir_use_symlinks=False)
except Exception as exc:
    print(f"Hugging Face Demucs MLX snapshot download failed: {exc!r}", file=sys.stderr)
    sys.exit(1)
PYHFDOWNLOAD
    then
      echo "      ⚠️  Hugging Face preconverted MLX weight download failed; falling back to conversion/inference preload."
    fi

    # Some demucs-mlx versions read ~/.cache/demucs-mlx through XDG_CACHE_HOME,
    # while others probe mlx-weights/HF cache first. Put a small marker in the
    # app-local cache so failures are visible and inspectable from the bundle.
    if find "$hf_cache_dir" -type f \( -name '*.safetensors' -o -name '*.npz' -o -name '*.bin' -o -name '*.json' \) -size +1M -print -quit | grep -q .; then
      echo "      ✓ Preconverted MLX weights present in $hf_cache_dir"
    else
      echo "      ⚠️  Preconverted MLX weight cache still looks empty after Hugging Face download."
    fi

    local models="$DEMUCS_MLX_PRELOAD_MODELS"
    if [[ "$models" == "all" ]]; then
      models="htdemucs htdemucs_ft htdemucs_6s hdemucs_mmi mdx mdx_extra"
    fi
    echo "  • Smoke-testing/preloading MLX Demucs models into app bundle cache: $models"
    local preload_tmp="$RESOURCES_DIR/StemBackends/.preload"
    rm -rf "$preload_tmp"
    mkdir -p "$preload_tmp"
    local preload_wav="$preload_tmp/silence.wav"
    local preload_helper="$preload_tmp/preload_demucs_mlx.py"
    "$venv_py" - <<PYWAV
import math, wave, struct
path = "$preload_wav"
sr = 44100
# The Demucs MLX CLI can reject ultra-short clips during chunking/OLA. Use a
# tiny-but-real 8 second stereo WAV so the preload path exercises the same code
# as user audio without materially bloating the final bundle; the file is
# removed after packaging.
frames = sr * 8
with wave.open(path, 'wb') as f:
    f.setnchannels(2)
    f.setsampwidth(2)
    f.setframerate(sr)
    for n in range(frames):
        # Near-silence avoids denormal/silence-special-case bugs in audio loaders.
        sample = int(16 * math.sin(2 * math.pi * 220.0 * n / sr))
        f.writeframes(struct.pack('<hh', sample, sample))
print(path)
PYWAV

    cat > "$preload_helper" <<'PYHELPER'
import os
import shutil
import subprocess
import sys
from pathlib import Path

model = sys.argv[1]
audio = Path(sys.argv[2])
out_dir = Path(sys.argv[3])
wrapper = Path(sys.argv[4])
log_path = Path(sys.argv[5])

with log_path.open("w", encoding="utf-8") as log:
    def say(message):
        print(message)
        print(message, file=log, flush=True)

    say(f"LemmingsStudio Demucs MLX preload for {model}")
    say(f"python={sys.executable}")
    say(f"audio={audio}")
    say(f"out={out_dir}")
    say(f"XDG_CACHE_HOME={os.environ.get('XDG_CACHE_HOME')}")
    say(f"HF_HOME={os.environ.get('HF_HOME')}")
    say(f"MLX_WEIGHTS_CACHE={os.environ.get('MLX_WEIGHTS_CACHE')}")

    # Make venv console scripts visible even when build.sh was invoked from a
    # shell that does not have the bundled PythonVenv/bin on PATH.
    venv_bin = Path(sys.executable).resolve().parent
    os.environ["PATH"] = str(venv_bin) + os.pathsep + os.environ.get("PATH", "")
    say(f"PATH={os.environ.get('PATH')}")

    # Python on macOS betas/custom installs can lack a working trust store even
    # though pip itself succeeded. Force certifi for urllib/requests/HF downloads.
    try:
        import certifi
        cafile = certifi.where()
        os.environ.setdefault("SSL_CERT_FILE", cafile)
        os.environ.setdefault("REQUESTS_CA_BUNDLE", cafile)
        os.environ.setdefault("CURL_CA_BUNDLE", cafile)
        say(f"certifi={cafile}")
    except Exception as exc:
        say(f"certifi unavailable: {exc!r}")

    if os.environ.get("DEMUCS_MLX_ALLOW_INSECURE_SSL") == "1":
        try:
            import ssl
            ssl._create_default_https_context = ssl._create_unverified_context
            say("WARNING: insecure SSL fallback enabled for this packaging run")
        except Exception as exc:
            say(f"could not enable insecure SSL fallback: {exc!r}")

    ok = False

    # Preferred weight-only bootstrap. The demucs-mlx README documents this when
    # the convert extra is installed. This is much cleaner than relying solely on
    # full separation as a side effect.
    candidates = [venv_bin / "mlx-weights", shutil.which("mlx-weights")]
    converter = next((str(c) for c in candidates if c and Path(c).exists()), None)
    if converter:
        cmd = [converter, "convert", f"demucs/{model}"]
        say("running: " + " ".join(cmd))
        try:
            res = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, text=True)
            say(f"mlx-weights exit={res.returncode}")
            ok = ok or (res.returncode == 0)
        except Exception as exc:
            say(f"mlx-weights failed to start: {exc!r}")
    else:
        say("mlx-weights command not found; trying demucs-mlx inference fallback")

    # Always do a tiny real inference warm-up if possible. This verifies the
    # exact bundled wrapper, catches broken installs now, and also fills the
    # demucs-mlx native cache when it uses an internal cache path.
    cmd = [str(wrapper), "-n", model, "--shifts", "1", "--seed", "0", "-b", "1", "-o", str(out_dir), str(audio)]
    say("running: " + " ".join(cmd))
    try:
        res = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, text=True)
        say(f"demucs-mlx exit={res.returncode}")
        ok = ok or (res.returncode == 0)
    except Exception as exc:
        say(f"demucs-mlx failed to start: {exc!r}")

    # Final import/constructor smoke test. Some versions lazily fetch/convert
    # during Separator construction, so this can succeed even when CLI warm-up was
    # blocked by an audio-IO edge case.
    try:
        from demucs_mlx import Separator
        sep = Separator(model=model, shifts=1, seed=0)
        say(f"Separator constructed: {sep!r}")
        ok = True
    except Exception as exc:
        say(f"Separator construction failed: {exc!r}")

    sys.exit(0 if ok else 1)
PYHELPER

    local model preload_status=0 log_path
    for model in $models; do
      echo "    · Preloading $model"
      log_path="/tmp/lemmings-demucs-mlx-preload-$model.log"
      if ! PATH="$RESOURCES_DIR/PythonVenv/bin:$PATH" XDG_CACHE_HOME="$mlx_cache_root" HF_HOME="$mlx_cache_root/huggingface" HF_HUB_CACHE="$mlx_cache_root/huggingface/hub" MLX_WEIGHTS_CACHE="$mlx_cache_root/mlx-weights" DEMUCS_MLX_ALLOW_INSECURE_SSL="$DEMUCS_MLX_ALLOW_INSECURE_SSL" "$venv_py" "$preload_helper" "$model" "$preload_wav" "$preload_tmp/out-$model" "$backends_dir/demucs-mlx" "$log_path"; then
        preload_status=1
        echo "      ⚠️  Could not preload $model; see $log_path during this packaging run."
      fi
    done
    rm -rf "$preload_tmp"

    local cache_bytes=0 cache_human="0B"
    if command -v du >/dev/null 2>&1; then
      cache_human=$(du -sh "$mlx_cache_root" 2>/dev/null | awk '{print $1}' || echo "0B")
    fi
    if command -v python3 >/dev/null 2>&1; then
      cache_bytes=$(python3 - <<PYSIZE
import os
root = "$mlx_cache_root"
total = 0
for base, _, files in os.walk(root):
    for name in files:
        try:
            total += os.path.getsize(os.path.join(base, name))
        except OSError:
            pass
print(total)
PYSIZE
)
    fi

    local has_weight_files=0
    if find "$mlx_cache_root" -type f \( -name '*.th' -o -name '*.safetensors' -o -name '*.npz' -o -name '*.bin' \) -size +1M -print -quit | grep -q .; then
      has_weight_files=1
    fi

    if [[ "$preload_status" -ne 0 || "$has_weight_files" -ne 1 ]]; then
      cat > "$backends_dir/DEMUCS_MLX_PRELOAD_WARNING.txt" <<TXT
build.sh attempted to preload MLX Demucs weights but the bundled cache is incomplete.
The app can still run MLX Demucs; missing weights may download/convert on first use.
Requested models: $models
Package spec: $DEMUCS_MLX_PIP_SPEC
Conversion/preload spec: $DEMUCS_MLX_CONVERT_PIP_SPEC
Hugging Face repo: $DEMUCS_MLX_HF_REPO
Cache directory: Contents/Resources/StemBackends/ModelCache
Cache size at packaging: $cache_human ($cache_bytes bytes)
Strict mode: DEMUCS_MLX_PRELOAD_STRICT=$DEMUCS_MLX_PRELOAD_STRICT
TXT
      echo "      ⚠️  MLX Demucs bundle cache incomplete: $cache_human at $mlx_cache_root"
      if [[ "$DEMUCS_MLX_PRELOAD_STRICT" == "1" ]]; then
        echo "      ❌ DEMUCS_MLX_PRELOAD_STRICT=1: failing packaging because requested weights were not bundled." >&2
        return 1
      fi
    else
      echo "      ✓ MLX Demucs bundled cache populated: $cache_human"
    fi
  else
    echo "  • MLX Demucs weight preloading disabled/skipped (DEMUCS_MLX_PRELOAD_WEIGHTS=$DEMUCS_MLX_PRELOAD_WEIGHTS)"
  fi

  # Trim temporary Python bytecode, but keep downloaded model caches intact.
  find "$RESOURCES_DIR/StemBackends/ModelCache" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

  cat > "$backends_dir/DEMUCS_MLX_BUNDLE_NOTE.txt" <<TXT
LemmingsStudio build.sh installed $DEMUCS_MLX_PIP_SPEC into Contents/Resources/PythonVenv
and created demucs-mlx/mlx-demucs wrapper launchers here.

Weight preloading is controlled by:
  DEMUCS_MLX_PRELOAD_WEIGHTS=$DEMUCS_MLX_PRELOAD_WEIGHTS
  DEMUCS_MLX_PRELOAD_MODELS=$DEMUCS_MLX_PRELOAD_MODELS
  DEMUCS_MLX_CONVERT_PIP_SPEC=$DEMUCS_MLX_CONVERT_PIP_SPEC
  DEMUCS_MLX_ALLOW_INSECURE_SSL=$DEMUCS_MLX_ALLOW_INSECURE_SSL
  DEMUCS_MLX_PRELOAD_STRICT=$DEMUCS_MLX_PRELOAD_STRICT
  DEMUCS_MLX_HF_REPO=$DEMUCS_MLX_HF_REPO

By default on Apple Silicon, build.sh preloads:
  htdemucs htdemucs_ft htdemucs_6s

The wrapper sets XDG_CACHE_HOME/HF_HOME/HF_HUB_CACHE/MLX_WEIGHTS_CACHE under
Contents/Resources/StemBackends/ModelCache so the bundled backend prefers the
app-local model cache instead of redownloading to the user's home folder.
TXT
}
# Python runtime + Demucs venv for stem splitting. Ollama models are intentionally not bundled.
embed_python_runtime
install_demucs_venv
install_demucs_mlx_backend



find_carla_app() {
  local candidate
  if [[ -n "$CARLA_APP" && -d "$CARLA_APP" ]]; then
    printf '%s\n' "$CARLA_APP"
    return 0
  fi

  for candidate in \
    "$RESOURCES_DIR/Helpers/Carla.app" \
    "$HOME/Library/Application Support/LemmingsStudio/PluginHosts/Carla.app" \
    /Applications/Carla.app \
    /Applications/Carla2.app \
    /opt/homebrew/Caskroom/carla/*/Carla.app \
    /usr/local/Caskroom/carla/*/Carla.app \
    /opt/homebrew/Cellar/carla/*/Carla.app \
    /usr/local/Cellar/carla/*/Carla.app
  do
    for expanded in $candidate; do
      if [[ -d "$expanded" ]]; then
        printf '%s\n' "$expanded"
        return 0
      fi
    done
  done

  return 1
}

find_carla_executable() {
  local candidate expanded
  if [[ -n "${CARLA_BIN:-}" && -x "$CARLA_BIN" ]]; then
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
    /usr/local/Cellar/carla/*/bin/carla \
    /opt/homebrew/Cellar/carla/*/lib/carla/carla \
    /usr/local/Cellar/carla/*/lib/carla/carla
  do
    for expanded in $candidate; do
      if [[ -x "$expanded" ]]; then
        printf '%s\n' "$expanded"
        return 0
      fi
    done
  done
  return 1
}

find_carla_single_executable() {
  local candidate expanded carla_bin dir
  if [[ -n "${CARLA_SINGLE_BIN:-}" && -x "$CARLA_SINGLE_BIN" ]]; then
    printf '%s\n' "$CARLA_SINGLE_BIN"
    return 0
  fi
  if command -v carla-single >/dev/null 2>&1; then
    command -v carla-single
    return 0
  fi
  carla_bin="$(find_carla_executable 2>/dev/null || true)"
  if [[ -n "$carla_bin" ]]; then
    dir="$(dirname "$carla_bin")"
    if [[ -x "$dir/carla-single" ]]; then
      printf '%s\n' "$dir/carla-single"
      return 0
    fi
  fi
  for candidate in \
    /opt/homebrew/bin/carla-single \
    /usr/local/bin/carla-single \
    /opt/homebrew/Cellar/carla/*/bin/carla-single \
    /usr/local/Cellar/carla/*/bin/carla-single \
    /opt/homebrew/Cellar/carla/*/lib/carla/carla-single \
    /usr/local/Cellar/carla/*/lib/carla/carla-single
  do
    for expanded in $candidate; do
      if [[ -x "$expanded" ]]; then
        printf '%s\n' "$expanded"
        return 0
      fi
    done
  done
  return 1
}

make_carla_launcher_app() {
  local app_path="$1"
  local carla_bin="$2"
  rm -rf "$app_path"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
  cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>CarlaLauncher</string>
  <key>CFBundleIdentifier</key><string>studio.lemmings.carla.launcher</string>
  <key>CFBundleName</key><string>Carla</string>
  <key>CFBundleDisplayName</key><string>Carla</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.5</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
  cat > "$app_path/Contents/MacOS/CarlaLauncher" <<SH
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
if [[ -x "$carla_bin" ]]; then
  exec "$carla_bin" "\$@"
fi
if command -v carla >/dev/null 2>&1; then
  exec carla "\$@"
fi
osascript -e 'display alert "Carla executable not found" message "Install Carla with Homebrew, or rebuild LemmingsStudio with CARLA_BIN=/path/to/carla."' >/dev/null 2>&1 || true
exit 127
SH
  chmod +x "$app_path/Contents/MacOS/CarlaLauncher"
  cat > "$app_path/Contents/LEMMINGS_BUNDLE_NOTE.txt" <<TXT
This wrapper app was generated by LemmingsStudio build.sh because Homebrew installed
Carla as a command-line formula rather than a standalone Carla.app. It launches:
$carla_bin
TXT
}

try_install_carla() {
  [[ "$AUTO_INSTALL_CARLA" != "0" ]] || return 1
  command -v brew >/dev/null 2>&1 || return 1

  echo "  • Carla not found; attempting Homebrew install for Carla bridge"
  # Formula/cask naming differs across setups. Try the cask first because it is most
  # likely to produce a self-contained Carla.app; then try the formula as fallback.
  if brew install --cask carla; then
    return 0
  fi
  if brew install carla; then
    return 0
  fi
  return 1
}

bundle_carla_host() {
  [[ "$EMBED_CARLA" != "0" ]] || { echo "  • Carla bundling disabled (EMBED_CARLA=0)"; return 0; }

  local carla=""
  if ! carla="$(find_carla_app 2>/dev/null)"; then
    if try_install_carla; then
      carla="$(find_carla_app 2>/dev/null || true)"
    fi
  fi

  local helpers="$RESOURCES_DIR/Helpers"
  mkdir -p "$helpers"

  if [[ -z "$carla" || ! -d "$carla" ]]; then
    local carla_bin=""
    carla_bin="$(find_carla_executable 2>/dev/null || true)"
    if [[ -n "$carla_bin" && -x "$carla_bin" ]]; then
      echo "  • Homebrew installed Carla as CLI-only; bundling direct Carla CLI launcher: $carla_bin"
      rm -rf "$helpers/Carla.app"
      mkdir -p "$helpers/CarlaFormula"
      cat > "$helpers/CarlaFormula/carla" <<SH
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
if [[ -x "$carla_bin" ]]; then
  exec "$carla_bin" "\$@"
fi
if command -v carla >/dev/null 2>&1; then
  exec carla "\$@"
fi
exit 127
SH
      chmod +x "$helpers/CarlaFormula/carla"
      local carla_single_bin=""
      carla_single_bin="$(find_carla_single_executable 2>/dev/null || true)"
      if [[ -n "$carla_single_bin" && -x "$carla_single_bin" ]]; then
        cat > "$helpers/CarlaFormula/carla-single" <<SH
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
if [[ -x "$carla_single_bin" ]]; then
  exec "$carla_single_bin" "\$@"
fi
if command -v carla-single >/dev/null 2>&1; then
  exec carla-single "\$@"
fi
exit 127
SH
        chmod +x "$helpers/CarlaFormula/carla-single"
      fi
      cat > "$helpers/CarlaFormula/README.txt" <<TXT
This launcher was generated because Homebrew installed Carla as a CLI formula,
not as a Carla.app bundle. LemmingsStudio launches this directly with Process,
not through LaunchServices, to avoid the fake-app “not responding” state.
Source executable: $carla_bin
Single plug-in helper: ${carla_single_bin:-not found}
TXT
    else
      echo "  ⚠️  Carla.app/CLI was not found; VST/VST3 bridge will use external discovery only."
      echo "     Install Carla manually, run with CARLA_APP=/path/to/Carla.app, CARLA_BIN=/path/to/carla, or set AUTO_INSTALL_CARLA=1."
      return 0
    fi
  else
    echo "  • Bundling Carla bridge host: $carla"
    rm -rf "$helpers/Carla.app"
    ditto --norsrc "$carla" "$helpers/Carla.app"
  fi

  cat > "$helpers/CARLA_LICENSE_NOTE.txt" <<'TXT'
Carla is GPL-2.0-or-later. If this binary is distributed inside LemmingsStudio,
ship Carla's license and corresponding source offer/source link as required by
the GPL. For closed/internal beta builds, you may prefer EMBED_CARLA=0 and rely
on the user's existing Carla install instead.
TXT

  if [[ -d "$helpers/Carla.app/Contents" ]]; then
    cat > "$helpers/Carla.app/Contents/LEMMINGS_BUNDLE_NOTE.txt" <<'TXT'
This Carla.app copy was bundled by LemmingsStudio build.sh as an optional plug-in
bridge host for VST/VST3/AU fallback workflows. It is not modified by LemmingsStudio.
TXT
    if command -v codesign >/dev/null 2>&1; then
      echo "  • Ad-hoc codesigning bundled Carla.app"
      codesign --force --deep --sign - "$helpers/Carla.app" >/dev/null 2>&1 || true
    fi
  fi
}

install_voice_venv_deps() {
  [[ "$EMBED_PYTHON" != "0" ]] || return 0
  [[ "$EMBED_RVC" != "0" ]] || { echo "  • Voice model/RVC deps disabled (EMBED_RVC=0)"; return 0; }
  local venv_py="$RESOURCES_DIR/PythonVenv/bin/python3"
  if [[ ! -x "$venv_py" ]]; then
    echo "  ⚠️  PythonVenv/bin/python3 missing; voice conversion deps will not be embedded."
    return 0
  fi

  local py_version
  py_version="$($venv_py - <<'PYVER'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PYVER
)"
  local py_major="${py_version%%.*}"
  local py_minor="${py_version#*.}"
  local skip_legacy_numba=0
  if (( py_major > 3 || (py_major == 3 && py_minor >= 12) )) && [[ "$RVC_ALLOW_LEGACY_NUMBA" != "1" ]]; then
    skip_legacy_numba=1
  fi

  echo "  • Installing full RVC/voice-conversion deps into bundled python3 venv"
  echo "    Python: $py_version"
  echo "    Core specs: $RVC_PIP_SPEC"
  if [[ "$RVC_INSTALL_PYPI_ADAPTERS" != "1" ]]; then
    echo "    PyPI RVC adapters disabled by default; using bundled RVC WebUI runtime/assets instead."
    echo "    Set RVC_INSTALL_PYPI_ADAPTERS=1 only on a known-compatible Python if you need rvc-python/rvc-inferpy."
  fi
  if [[ "$skip_legacy_numba" == "1" ]]; then
    echo "    Legacy numba/llvmlite pins are disabled on Python $py_version; set RVC_ALLOW_LEGACY_NUMBA=1 to force them."
  fi
  [[ -z "$RVC_OPTIONAL_PIP_SPEC" ]] || echo "    Optional/full-fat legacy specs: $RVC_OPTIONAL_PIP_SPEC"

  "$venv_py" -m pip install --upgrade pip setuptools wheel || true

  local failed=()
  local skipped=()
  local spec spec_name
  for spec in $RVC_PIP_SPEC; do
    spec_name="$(printf '%s' "$spec" | sed -E 's/[<>=!~].*$//' | sed -E 's/\[.*\]$//' | tr '[:upper:]_' '[:lower:]-')"
    if [[ "$skip_legacy_numba" == "1" && ( "$spec_name" == "numba" || "$spec_name" == "llvmlite" ) ]]; then
      echo "    - $spec (skipped on Python $py_version; legacy RVC pins do not support this Python)"
      skipped+=("$spec")
      continue
    fi
    echo "    - $spec"
    if "$venv_py" -m pip install "$spec"; then
      continue
    fi
    echo "      ⚠️  $spec failed; retrying with --break-system-packages"
    if "$venv_py" -m pip install "$spec" --break-system-packages; then
      continue
    fi
    echo "      ⚠️  Voice dependency failed: $spec"
    failed+=("$spec")
  done

  # Legacy optional dependencies such as fairseq must never break packaging.
  # They are opt-in only and are isolated from the required RVC dependency set.
  local optional_failed=()
  for spec in $RVC_OPTIONAL_PIP_SPEC; do
    echo "    - full-fat optional $spec"
    if "$venv_py" -m pip install "$spec"; then
      continue
    fi
    echo "      ⚠️  Optional dependency failed; retrying with --break-system-packages: $spec"
    if "$venv_py" -m pip install "$spec" --break-system-packages; then
      continue
    fi
    echo "      ⚠️  Optional dependency skipped without failing build: $spec"
    optional_failed+=("$spec")
  done

  if [[ ${#failed[@]} -gt 0 || ${#skipped[@]} -gt 0 ]]; then
    {
      if [[ ${#failed[@]} -gt 0 ]]; then
        echo "Some required RVC/voice-conversion dependencies failed to install during packaging."
        printf '%s\n' "${failed[@]}"
        echo ""
      fi
      if [[ ${#skipped[@]} -gt 0 ]]; then
        echo "Some legacy RVC dependencies were intentionally skipped on Python $py_version."
        printf '%s\n' "${skipped[@]}"
        echo ""
      fi
      echo "The app bundle was still created and the full RVC runtime/assets were still packaged where possible."
      echo "For old numba/llvmlite/RVC requirement pins, use Python 3.10/3.11 and rerun: PYTHON_BIN=/path/to/python3 ./build.sh"
      echo "To force the old numba path anyway, set RVC_ALLOW_LEGACY_NUMBA=1."
    } > "$RESOURCES_DIR/voice-dependency-warnings.txt"
    echo "  ⚠️  Voice dependency warnings written to Contents/Resources/voice-dependency-warnings.txt"
  fi

  if [[ ${#optional_failed[@]} -gt 0 ]]; then
    {
      echo "Optional legacy RVC dependencies were skipped without failing packaging."
      printf '%s\n' "${optional_failed[@]}"
      echo ""
      echo "This is expected for fairseq/rvc-python/rvc-inferpy on newer Python/macOS builds."
      echo "Use RVC_TRY_FAIRSEQ=1 and/or RVC_INSTALL_PYPI_ADAPTERS=1 with Python 3.10/3.11 only if a specific RVC fork needs it."
    } > "$RESOURCES_DIR/voice-optional-dependency-warnings.txt"
    echo "  ⚠️  Optional voice dependency warnings written to Contents/Resources/voice-optional-dependency-warnings.txt"
  fi
}

bundle_rvc_runtime_and_assets() {
  [[ "$EMBED_PYTHON" != "0" ]] || return 0
  [[ "$EMBED_RVC" != "0" ]] || { echo "  • RVC runtime bundling disabled (EMBED_RVC=0)"; return 0; }
  local venv_py="$RESOURCES_DIR/PythonVenv/bin/python3"
  if [[ ! -x "$venv_py" ]]; then
    echo "  ⚠️  PythonVenv/bin/python3 missing; skipping RVC runtime/assets."
    return 0
  fi

  local voice_dir="$RESOURCES_DIR/Voice"
  local rvc_root="$voice_dir/RVC-WebUI"
  local asset_note="$voice_dir/RVC_BUNDLE_MANIFEST.txt"
  mkdir -p "$voice_dir"

  echo "  • Bundling full RVC runtime"
  echo "    Repo: $RVC_RUNTIME_REPO"
  echo "    Ref:  $RVC_RUNTIME_REF"
  rm -rf "$rvc_root"
  if command -v git >/dev/null 2>&1; then
    if git clone --depth 1 --branch "$RVC_RUNTIME_REF" "$RVC_RUNTIME_REPO" "$rvc_root"; then
      echo "    ✓ RVC runtime cloned"
    else
      echo "    ⚠️  Branch clone failed; retrying default branch then checkout"
      rm -rf "$rvc_root"
      if git clone --depth 1 "$RVC_RUNTIME_REPO" "$rvc_root"; then
        (cd "$rvc_root" && git fetch --depth 1 origin "$RVC_RUNTIME_REF" && git checkout FETCH_HEAD) || true
      fi
    fi
  else
    echo "    ⚠️  git not found; RVC runtime repo was not cloned."
  fi

  if [[ -d "$rvc_root" ]]; then
    rm -rf "$rvc_root/.git" "$rvc_root/.github" "$rvc_root/logs" "$rvc_root/TEMP" "$rvc_root/audios" 2>/dev/null || true
    find "$rvc_root" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
    find "$rvc_root" \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
    if [[ -f "$rvc_root/requirements.txt" ]]; then
      echo "  • Installing RVC runtime requirements.txt"
      local filtered_requirements="$voice_dir/rvc-requirements.filtered.txt"
      python3 - "$rvc_root/requirements.txt" "$filtered_requirements" <<'PYREQ'
import pathlib, sys
src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2])
blocked = {
    # Known build-breakers on macOS/new Python. Full RVC packaging still ships
    # the runtime repo and model assets; these helper packages/binaries are not
    # allowed to fail app packaging.
    "fairseq",
    "aria2",
    "rvc-python",
    "rvc_inferpy",
    "rvc-inferpy",
}
# Some upstream RVC requirement files contain historical pins that force source
# builds on Python 3.12+ / 3.14 and explode before wheels can be resolved.
# Keep the app's already-installed modern numpy/faiss stack instead.
fragile_prefixes = ("numpy<=", "numpy==1.25", "faiss-cpu==1.7", "faiss-cpu<1.8", "numba==", "numba<=", "llvmlite==", "llvmlite<=")
blocked_on_modern_python = {"numba", "llvmlite"}
lines = []
for raw in src.read_text(errors="ignore").splitlines():
    stripped = raw.strip()
    lowered = stripped.lower()
    name = stripped.split("==", 1)[0].split(">=", 1)[0].split("<=", 1)[0].split("~=", 1)[0].split("<", 1)[0].split("[", 1)[0].strip().lower().replace("_", "-")
    if not stripped or stripped.startswith("#"):
        lines.append(raw)
        continue
    if name in {x.replace("_", "-") for x in blocked} or lowered.startswith(fragile_prefixes) or name in blocked_on_modern_python:
        lines.append(f"# skipped by LemmingsStudio build.sh because this requirement is fragile on newer Python/macOS: {raw}")
        continue
    lines.append(raw)
dst.write_text("\n".join(lines) + "\n")
PYREQ
      "$venv_py" -m pip install -r "$filtered_requirements" || {
        echo "    ⚠️  Filtered RVC requirements.txt failed; continuing with explicit bundled specs."
      }
      if grep -qi '^# skipped by LemmingsStudio build.sh because' "$filtered_requirements" 2>/dev/null; then
        echo "    • fragile RVC requirements were filtered out by default (fairseq/aria2/old numpy/faiss/numba/llvmlite/PyPI adapters)."
        echo "      Set RVC_TRY_FAIRSEQ=1, RVC_ALLOW_LEGACY_NUMBA=1, or RVC_INSTALL_PYPI_ADAPTERS=1 only on a known-compatible Python if needed."
      fi
    fi
  fi

  echo "  • Downloading RVC pretrained assets/weights"
  echo "    HF repo: $RVC_ASSETS_HF_REPO"
  local allow_patterns_py
  if [[ "$RVC_PRELOAD_ALL" == "1" ]]; then
    allow_patterns_py="None"
    echo "    Mode: full snapshot (RVC_PRELOAD_ALL=1, can be massive)"
  else
    allow_patterns_py="$(printf '%s\n' $RVC_ALLOW_PATTERNS | python3 -c 'import json,sys; print(json.dumps([x.strip() for x in sys.stdin if x.strip()]))')"
    echo "    Allow patterns: $RVC_ALLOW_PATTERNS"
  fi

  RVC_TARGET_ROOT="$rvc_root" RVC_ASSETS_HF_REPO="$RVC_ASSETS_HF_REPO" RVC_ALLOW_PATTERNS_JSON="$allow_patterns_py" "$venv_py" - <<'PYRVC' || true
import json, os, pathlib, sys
root = pathlib.Path(os.environ["RVC_TARGET_ROOT"])
repo = os.environ["RVC_ASSETS_HF_REPO"]
allow_raw = os.environ.get("RVC_ALLOW_PATTERNS_JSON", "None")
allow = None if allow_raw == "None" else json.loads(allow_raw)
root.mkdir(parents=True, exist_ok=True)
try:
    from huggingface_hub import snapshot_download
except Exception as exc:
    print(f"huggingface_hub missing: {exc}", file=sys.stderr)
    raise SystemExit(2)
cache = snapshot_download(repo_id=repo, allow_patterns=allow, local_dir=str(root), local_dir_use_symlinks=False)
print(cache)
PYRVC

  # Normalize common asset locations expected by RVC forks.
  if [[ -d "$rvc_root" ]]; then
    mkdir -p "$rvc_root/assets/hubert" "$rvc_root/assets/rmvpe"
    [[ -f "$rvc_root/hubert_base.pt" && ! -f "$rvc_root/assets/hubert/hubert_base.pt" ]] && cp "$rvc_root/hubert_base.pt" "$rvc_root/assets/hubert/hubert_base.pt" || true
    [[ -f "$rvc_root/rmvpe.pt" && ! -f "$rvc_root/assets/rmvpe/rmvpe.pt" ]] && cp "$rvc_root/rmvpe.pt" "$rvc_root/assets/rmvpe/rmvpe.pt" || true
    [[ -f "$rvc_root/rmvpe.onnx" && ! -f "$rvc_root/assets/rmvpe/rmvpe.onnx" ]] && cp "$rvc_root/rmvpe.onnx" "$rvc_root/assets/rmvpe/rmvpe.onnx" || true
    # Some WebUI builds look for pretrained folders under assets/; mirror without
    # deleting the original HF layout.
    for d in pretrained pretrained_v2 pretrained_v0 uvr5_weights infer_pack; do
      if [[ -d "$rvc_root/$d" && ! -e "$rvc_root/assets/$d" ]]; then
        cp -R "$rvc_root/$d" "$rvc_root/assets/$d" 2>/dev/null || true
      fi
    done
  fi

  local missing=()
  [[ -f "$rvc_root/assets/hubert/hubert_base.pt" ]] || missing+=("assets/hubert/hubert_base.pt")
  [[ -f "$rvc_root/assets/rmvpe/rmvpe.pt" || -f "$rvc_root/assets/rmvpe/rmvpe.onnx" ]] || missing+=("assets/rmvpe/rmvpe.pt or rmvpe.onnx")
  [[ -d "$rvc_root/assets/pretrained_v2" || -d "$rvc_root/pretrained_v2" || -d "$rvc_root/assets/pretrained" || -d "$rvc_root/pretrained" ]] || missing+=("pretrained/pretrained_v2 generator/discriminator weights")

  {
    echo "RVC bundled by LemmingsStudio build.sh"
    echo "Runtime repo: $RVC_RUNTIME_REPO"
    echo "Runtime ref: $RVC_RUNTIME_REF"
    echo "Asset repo: $RVC_ASSETS_HF_REPO"
    echo "Preload all: $RVC_PRELOAD_ALL"
    echo "Allow patterns: $RVC_ALLOW_PATTERNS"
    echo "Expected root: Contents/Resources/Voice/RVC-WebUI"
    echo ""
    echo "Important: RVC model files may be PyTorch pickle checkpoints. Only ship/use consent-cleared voice models from trusted sources."
    if [[ ${#missing[@]} -gt 0 ]]; then
      echo ""
      echo "Missing expected assets:"
      printf ' - %s\n' "${missing[@]}"
    fi
  } > "$asset_note"

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "  ⚠️  RVC bundle is missing expected assets: ${missing[*]}"
    if [[ "$RVC_PRELOAD_STRICT" == "1" ]]; then
      echo "  ❌ RVC_PRELOAD_STRICT=1, failing packaging."
      exit 1
    fi
  fi
}

# Voice conversion/RVC runtime/deps live in the same bundled python3 venv.
install_voice_venv_deps
bundle_rvc_runtime_and_assets

# Optional Carla bridge host for VST/VST3 and awkward AU plug-ins.
bundle_carla_host

# Icon.
if [[ -d "Icon/AppIcon.iconset" ]] && command -v iconutil >/dev/null 2>&1; then
  echo "  • Generating AppIcon.icns"
  iconutil -c icns "Icon/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"
elif [[ -f "Icon/AppIcon.icns" ]]; then
  copy_item "Icon/AppIcon.icns" "$RESOURCES_DIR"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION_SHORT</string>
  <key>CFBundleVersion</key><string>$APP_BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key><string>LemmingsStudio uses the microphone or selected audio input device to record audio tracks and Voice AI takes.</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>LemmingsStudio Splice OAuth</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>lemmingsstudio</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if command -v install_name_tool >/dev/null 2>&1; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
fi

# Keep a tiny manifest for sanity checks.
{
  echo "LemmingsStudio packaged $(date)"
  echo "Executable: Contents/MacOS/$APP_NAME"
  echo "Resources:"; find "$RESOURCES_DIR" -maxdepth 2 -print | sed "s#^$APP_BUNDLE/##"
  echo "Frameworks:"; find "$FRAMEWORKS_DIR" -maxdepth 2 -print | sed "s#^$APP_BUNDLE/##"
} > "$RESOURCES_DIR/packaging-manifest.txt"

if command -v codesign >/dev/null 2>&1; then
  # Microphone (TCC) permission is bound to the app's CODE SIGNATURE. Ad-hoc
  # signing (`--sign -`) produces a *different* signature every build, so macOS
  # treats each rebuild as a new app and the granted mic permission DOES NOT
  # persist — CoreAudio then delivers silence across every capture API. To make
  # the grant stick, sign with a STABLE identity.
  #
  # Pick an identity in priority order:
  #   1) $LEMMINGS_SIGN_IDENTITY (set this to a Developer ID / Apple Dev cert name)
  #   2) a persistent self-signed cert named "LemmingsStudio Local" (see below)
  #   3) ad-hoc (last resort — mic permission will reset on every rebuild)
  SIGN_ID=""
  if [ -n "${LEMMINGS_SIGN_IDENTITY:-}" ]; then
    SIGN_ID="$LEMMINGS_SIGN_IDENTITY"
  elif security find-identity -v -p codesigning 2>/dev/null | grep -q "LemmingsStudio Local"; then
    SIGN_ID="LemmingsStudio Local"
  fi

  ENTITLEMENTS="$DIST_DIR/lemmings.entitlements"
  cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
PLIST

  if [ -n "$SIGN_ID" ]; then
    echo "  • Codesigning with stable identity: $SIGN_ID (mic permission will persist)"
    codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP_BUNDLE" >/dev/null
  else
    echo "  • Ad-hoc codesigning (⚠️  mic permission will RESET every rebuild)"
    echo "    To make recording permission persist, create a one-time self-signed cert:"
    echo "      1) Keychain Access ▸ Certificate Assistant ▸ Create a Certificate…"
    echo "         Name: 'LemmingsStudio Local',  Identity Type: Self Signed Root,"
    echo "         Certificate Type: Code Signing"
    echo "      2) Rebuild — this script will auto-detect and use it."
    echo "    Or run once now if a prior grant is stuck:  tccutil reset Microphone $BUNDLE_ID"
    codesign --force --deep --entitlements "$ENTITLEMENTS" --sign - "$APP_BUNDLE" >/dev/null
  fi
fi

echo ""
echo "✅ Build succeeded."
echo "✅ App bundle: $(pwd)/$APP_BUNDLE"
echo "   Launch: open \"$APP_BUNDLE\""
echo "   Reveal: open -R \"$APP_BUNDLE\""
echo "   Size: $(du -sh "$APP_BUNDLE" | awk '{print $1}')"
echo ""
echo "Note: .build/xcode/Build/Products/$CONFIG will still show the raw Unix executable."
echo "That is normal SwiftPM output. The app bundle is in ./dist/."
echo "Ollama models are intentionally external and are not bundled."
echo "Demucs is bundled in Contents/Resources/PythonVenv using bin/python3 unless EMBED_DEMUCS=0 was used."
echo "On Apple Silicon, build.sh also bundles Demucs MLX wrappers in Contents/Resources/StemBackends unless EMBED_DEMUCS_MLX=0 was used."
echo "Full RVC runtime/deps/assets are bundled into Contents/Resources/Voice and PythonVenv unless EMBED_RVC=0 was used."
echo "Carla.app is bundled into Contents/Resources/Helpers when found; CLI-only Carla is bundled as Contents/Resources/Helpers/CarlaFormula/carla and carla-single when available unless EMBED_CARLA=0 was used."
echo "Use CARLA_APP=/path/to/Carla.app ./build.sh to bundle a specific Carla build."
echo "Use CARLA_BIN=/path/to/carla ./build.sh when Homebrew installed CLI-only Carla."
echo "Fairseq/aria2/legacy numba pins/PyPI RVC adapters are skipped by default so they cannot break packaging; use RVC_TRY_FAIRSEQ=1, RVC_ALLOW_LEGACY_NUMBA=1, or RVC_INSTALL_PYPI_ADAPTERS=1 with Python 3.10/3.11 to opt in."
echo "Set AUTO_INSTALL_OLLAMA=1 ./build.sh to install Homebrew/Ollama during packaging when missing."
