# Buildfix160 — Stem Split MLX fallback + 4-stem model guard

## Why
The buildfix159 diagnostics showed a real MLX Demucs runtime crash:

`RuntimeError: There is no Stream(gpu, 1) in current thread.`

The popup was working, but a selected MLX backend could still die before importing stems.
The popup also defaulted to `htdemucs_6s`, even when the user only selected vocals/drums/bass/other, forcing a fragile 6-stem path for normal 4-stem work.

## Changes
- Default Stem Split popup model is now `htdemucs`, not `htdemucs_6s`.
- If the user selects `htdemucs_6s` but only requests 4-stem targets, LemmingsStudio automatically uses `htdemucs`.
- Manual MLX/Core ML backend failures can now auto-fallback to official Demucs when official Demucs is available.
- MLX-specific `No Stream(gpu...)` / current-thread errors now include an explicit hint.
- Stem subprocesses now run with deterministic env settings like `PYTHONUNBUFFERED=1` and `TOKENIZERS_PARALLELISM=false`.

## Scope guard
No recording, code signing, Splice, Serum/hosted plugin, AU hosting, RVC/build.sh, Demucs packaging, export, mixer clipping, warp, metronome/count-in, or Finder import changes.
