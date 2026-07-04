# Buildfix 218 – Windows ARM64 stem backend graceful degradation

## Why

Native Windows ARM64 Python currently trips over Demucs' dependency stack:

- `torchaudio` has no matching wheel in the PyTorch CPU index for the observed `cp311-win_arm64` setup.
- `librosa` pulls packages such as `numba`, `llvmlite`, and `soxr`; on this machine those fell back to local wheel builds and required MSVC/CMake/NMake.
- That made backend setup fail even though the rest of the Windows app does not require Demucs.

## Changes

- `scripts/setup-backend.ps1`
  - Detects native Windows ARM64 Python.
  - Installs a safe dependency set on native Windows ARM64 instead of pulling `librosa`/Demucs dependencies that compile from source.
  - Installs `torch` opportunistically, but skips mandatory `torchaudio`/Demucs on native Windows ARM64.
  - Writes backend capability metadata with `stems=unavailable` and a human-readable reason.
  - Keeps the unsupported escape hatch: set `LEMMINGS_EXPERIMENTAL_WINARM64_STEMS=1` to try source builds manually.

- `backend/stem_runner.py`
  - Probes whether `demucs`, `torch`, and `torchaudio` are actually importable.
  - Prints a clear unavailable message instead of crashing with `ModuleNotFoundError`.
  - Returns exit code `12` when the Demucs runtime is unavailable.

- `build-installer.ps1`
  - Skips Demucs model preload/bundling for native `win-arm64` unless `LEMMINGS_EXPERIMENTAL_WINARM64_STEMS=1` is set.
  - Corrects the build manifest so it does not claim model weights were bundled when they were intentionally skipped.

## Recommended commands

Native Windows ARM64 build, app-first / no stem bundling:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-arm64
```

Full Demucs/stem build today:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels
```

The `win-x64` path can run under Windows-on-ARM emulation and is the practical route for Demucs until the Python audio/ML wheel ecosystem catches up for native Windows ARM64.
