# Buildfix118 — Demucs MLX cache validation and preconverted weight download

Buildfix117/116 could install the `demucs-mlx` package and write `DEMUCS_MLX_BUNDLE_NOTE.txt` even when no model weights were actually present in `Contents/Resources/StemBackends/ModelCache`.

This build makes the preload path honest and more robust:

- Installs `huggingface_hub[hf_xet]` next to `certifi` in the bundled Python venv.
- Downloads the preconverted MLX weight repository first, defaulting to `mlx-community/demucs-mlx`, into:

  `Contents/Resources/StemBackends/ModelCache/demucs-mlx`

- Keeps the older conversion/inference smoke-test fallback.
- Validates that the app-local cache contains real weight artifacts (`.safetensors`, `.npz`, `.bin`, `.th`) larger than 1 MB.
- Writes `DEMUCS_MLX_PRELOAD_WARNING.txt` when preload was requested but the cache is incomplete.
- Adds `DEMUCS_MLX_PRELOAD_STRICT=1` to fail packaging instead of silently shipping a no-weight bundle.

Recommended release build:

```bash
DEMUCS_MLX_PRELOAD_WEIGHTS=1 \
DEMUCS_MLX_PRELOAD_STRICT=1 \
DEMUCS_MLX_PRELOAD_MODELS="htdemucs htdemucs_ft htdemucs_6s" \
./build.sh
```

Emergency only, for broken local Python CA stores:

```bash
DEMUCS_MLX_ALLOW_INSECURE_SSL=1 \
DEMUCS_MLX_PRELOAD_WEIGHTS=1 \
DEMUCS_MLX_PRELOAD_STRICT=1 \
./build.sh
```
