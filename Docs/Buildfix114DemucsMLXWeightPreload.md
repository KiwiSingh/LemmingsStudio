# Buildfix 114 — Bundle Demucs MLX model weights

`build.sh` now does more than install the `demucs-mlx` Python package. On Apple Silicon, it preloads MLX Demucs model weights into the app bundle cache so first use does not have to download/convert them.

## Defaults

- `EMBED_DEMUCS_MLX=auto`
- `DEMUCS_MLX_PRELOAD_WEIGHTS=auto`
- `DEMUCS_MLX_PRELOAD_MODELS="htdemucs htdemucs_ft htdemucs_6s"`
- `DEMUCS_MLX_CONVERT_PIP_SPEC="demucs-mlx[convert]"`

The default model set covers the normal 4-stem path, the fine-tuned 4-stem path, and the 6-stem path that adds guitar and piano when the backend package/weights support it.

## App-local cache

The bundled `StemBackends/demucs-mlx` wrapper exports cache variables into:

```text
Contents/Resources/StemBackends/ModelCache
```

That keeps Demucs MLX / Hugging Face / mlx-weights caches next to the bundled runner instead of forcing first run to hit `~/.cache`.

## Controls

```bash
DEMUCS_MLX_PRELOAD_WEIGHTS=0 ./build.sh
DEMUCS_MLX_PRELOAD_MODELS="htdemucs" ./build.sh
DEMUCS_MLX_PRELOAD_MODELS="all" ./build.sh
```

`all` currently expands to:

```text
htdemucs htdemucs_ft htdemucs_6s hdemucs_mmi mdx mdx_extra
```

That can make the bundle much larger.
