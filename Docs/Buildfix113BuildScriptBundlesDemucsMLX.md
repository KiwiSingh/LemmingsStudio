# Buildfix113 — build.sh bundles Demucs MLX on Apple Silicon

This pass fixes the packaging gap from buildfix109: the app knew how to discover
Demucs MLX, but `build.sh` only created the official PyTorch Demucs venv.

Changes:

- Added `EMBED_DEMUCS_MLX` to `build.sh`. Default is `auto`: enabled on Apple
  Silicon macOS, skipped elsewhere.
- Added `DEMUCS_MLX_PIP_SPEC`, defaulting to `demucs-mlx`.
- After the bundled Python/Demucs venv is created, `build.sh` installs
  `demucs-mlx` into the same venv on Apple Silicon.
- `build.sh` now creates bundled runner wrappers at:
  - `Contents/Resources/StemBackends/demucs-mlx`
  - `Contents/Resources/StemBackends/mlx-demucs`
- `StemSplitter` now calls the Python `demucs-mlx` CLI with its documented
  arguments: `-n <model> -o <outDir> <input>`, instead of the earlier
  incompatible `--model/--out` form.

Notes:

- The bundled MLX backend is a runner/package bundle, not a forced huge weights
  bundle. Depending on the package version, model weights may still download or
  cache on first use.
- Official Demucs remains bundled as the compatibility fallback when
  `EMBED_DEMUCS=1`.
- Disable MLX packaging with `EMBED_DEMUCS_MLX=0 ./build.sh`.
