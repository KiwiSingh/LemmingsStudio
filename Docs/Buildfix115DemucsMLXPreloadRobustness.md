# Buildfix115 — Robust Demucs MLX weight preload

`build.sh` previously tried to preload MLX Demucs weights by running `demucs-mlx`
against a quarter-second silent WAV. That was too brittle: some Demucs MLX/audio
loader paths reject or mishandle ultra-short clips during chunking, so packaging
could warn that `htdemucs`, `htdemucs_ft`, and `htdemucs_6s` failed even though
the package itself had installed.

This build makes preload more robust:

- Generates an 8-second near-silent stereo WAV instead of a tiny 0.25s file.
- Installs the `demucs-mlx[convert]` extra as before.
- Uses a helper script that first tries the documented weight-only path:
  `mlx-weights convert demucs/<model>`.
- Then runs the bundled `demucs-mlx` wrapper as a real warm-up/inference smoke
  test with `--shifts 1 --seed 0 -b 1`.
- Then constructs `demucs_mlx.Separator(model: ...)` as a final smoke test for
  package versions that lazily load/convert at construction time.
- Logs the full environment and each command into
  `/tmp/lemmings-demucs-mlx-preload-<model>.log`.

The app-local cache remains:

```text
Contents/Resources/StemBackends/ModelCache
```

No Splice, DAW editing, AU hosting, or Sound Agent code was changed.
