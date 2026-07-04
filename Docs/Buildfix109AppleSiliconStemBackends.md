# Buildfix109 — Stem splitter backend choice + Apple Silicon acceleration hooks

This pass adds backend agency to LemmingsStudio's Stem Splitter instead of hard-coding official Python Demucs only.

## Backends

- Auto: on arm64 Macs, prefers MLX Demucs, then Core ML HTDemucs, then official Demucs.
- Demucs / PyTorch: official-compatible path via `python3 -m demucs`.
- Demucs MLX: Apple Silicon accelerated path, discovered via bundled `Resources/StemBackends/demucs-mlx`, `demucs-mlx`/`mlx-demucs` on PATH, `LEMMINGS_DEMUCS_MLX_BIN`, or `python3 -m demucs_mlx`.
- HTDemucs Core ML: experimental Apple-native fallback, discovered via bundled `htdemucs-coreml`, PATH, `LEMMINGS_HTDEMUCS_COREML_BIN`, or `python3 -m htdemucs_coreml`.

## Notes

Demucs MLX is the preferred Apple Silicon story because it keeps Demucs-style stems while avoiding the awkward PyTorch/MPS path. Core ML is treated as an alternative and shows a disclaimer because many Core ML conversions target 4-source HTDemucs, not necessarily the 6-source guitar/piano model.

The Splice integration is untouched.
