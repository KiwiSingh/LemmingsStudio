# Stem backend bundle hooks

LemmingsStudio discovers optional native stem-separation runners in this folder.

Expected bundled or user-provided runners:

- `demucs-mlx` / `mlx-demucs`: Apple Silicon MLX Demucs backend.
- `htdemucs-coreml`: optional Core ML HTDemucs backend.

`build.sh` can install Demucs MLX into the bundled Python venv and create the
`demucs-mlx` wrappers automatically on Apple Silicon. It also supports optional
model-weight preloading into:

```text
Contents/Resources/StemBackends/ModelCache
```

Useful build knobs:

```bash
EMBED_DEMUCS_MLX=0 ./build.sh
DEMUCS_MLX_PRELOAD_WEIGHTS=0 ./build.sh
DEMUCS_MLX_PRELOAD_MODELS="htdemucs" ./build.sh
DEMUCS_MLX_PRELOAD_MODELS="all" ./build.sh
```

Buildfix115 uses the documented `mlx-weights convert demucs/<model>` path when
available, then runs a small Demucs MLX warm-up to verify the exact bundled
wrapper. If preload fails, check:

```text
/tmp/lemmings-demucs-mlx-preload-<model>.log
```

Depending on the installed backend, 6-source splitting may require `htdemucs_6s`.
Core ML alternatives may expose only the standard 4 stems.

## buildfix116 preload note

If Demucs MLX model preloading fails with an SSL certificate verification error,
`build.sh` now installs `certifi` into the bundled Python environment and sets
`SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, and `CURL_CA_BUNDLE` for both preload and
runtime wrapper execution. It also prepends the bundled venv `bin` directory to
`PATH` so `mlx-weights` can be found after installing `demucs-mlx[convert]`.

Last resort only:

```bash
DEMUCS_MLX_ALLOW_INSECURE_SSL=1 ./build.sh
```
