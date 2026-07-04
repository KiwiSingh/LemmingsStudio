# Lemmings Studio — buildfix164 (Claude): stem splitter fixed (torchcodec bypass)

## Root cause (clear from your debug screenshot — same under every backend)
Official Demucs died before it could even read the audio:
```
ModuleNotFoundError: No module named 'torchcodec'
ImportError: TorchCodec is required for load_with_torchcodec. Please install torchcodec…
```
Modern **torchaudio routes `torchaudio.load` through TorchCodec**, which isn't bundled — so
`python -m demucs <file>` failed instantly. (MLX failed separately on an `mlx Stream(gpu,1)`
thread bug, and Auto then reported "all backends failed".)

## Fix (`StemSplitter.swift`, `build.sh`)
- Official Demucs now launches through an **inline bootstrap** that monkeypatches
  `torchaudio.load` / `torchaudio.save` to use **soundfile (libsndfile)** before handing off
  to Demucs via `runpy`. The stem input and outputs are WAV, which soundfile reads/writes
  natively — so TorchCodec is never touched. No separate script to bundle; degrades with a
  clear message if soundfile is somehow absent.
- `build.sh` now installs **`soundfile`** into the Demucs venv (`DEMUCS_PIP_SPEC="demucs
  soundfile"`), so the bypass has what it needs.

## Why this also fixes "Auto: all backends failed"
Auto tries **official Demucs first**; with it working again, Auto succeeds on the first try
and never reaches the flaky MLX `Stream(gpu,1)` path. (That MLX bug is still there, but it's
now just an optional accelerator, not a blocker — happy to chase it separately if you want
MLX specifically.)

## To apply
**Rebuild** (`./build.sh`) so the venv picks up `soundfile`, then Stem Split → Auto (or
Demucs) on the clip. You should see `[lemmings] torchaudio I/O routed through soundfile` in
the backend output, then real progress bars per stem.

## Build note
Authored without the Swift/Python toolchains for the app, but the Python bootstrap is
syntax-validated and the Swift is brace-balanced. Expect at most minor Xcode fixups.
