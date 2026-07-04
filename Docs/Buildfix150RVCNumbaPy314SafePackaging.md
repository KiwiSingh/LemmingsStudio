# Buildfix 150 — RVC Numba / Python 3.14 Safe Packaging

Buildfix149 stopped fairseq, aria2, and PyPI RVC adapters from breaking packaging, but upstream RVC `requirements.txt` can still pin legacy `numba==0.56.4` / `llvmlite` versions that only support older Python and fail on Python 3.14 before packaging can continue cleanly.

## Changes

- Added `RVC_ALLOW_LEGACY_NUMBA=0` default.
- `install_voice_venv_deps` now detects the bundled Python version.
- On Python 3.12+, `numba` and `llvmlite` are skipped by default unless explicitly forced.
- The RVC runtime requirements filter now skips fragile `numba` / `llvmlite` pins as well as fairseq, aria2, old numpy/faiss pins, and PyPI adapters.
- Warnings are written into `Contents/Resources/voice-dependency-warnings.txt` instead of failing the app bundle.

## Opt-in escape hatch

Use this only with an older compatible Python if a specific RVC fork really requires those pins:

```bash
RVC_ALLOW_LEGACY_NUMBA=1 PYTHON_BIN=/path/to/python3.10 ./build.sh
```

## Untouched

- Code signing logic
- Claude's recording fixes
- Splice MCP/download/preview
- Serum / Serum 2 / plugin hosting fixes
- AU hosting
- Demucs/stems
- Piano Roll
- Browser drag/drop
- Monitor modes
- Mixer FX
- Warp controls
- Metronome/count-in
