# Buildfix 148 — Fairseq-safe RVC packaging

This buildfix keeps the full-fat RVC packaging path from buildfix147, but makes
legacy Fairseq unable to break the build.

## Changes

- `fairseq` is no longer attempted by default.
- Added `RVC_TRY_FAIRSEQ=1` as an explicit opt-in for machines using a
  known-compatible Python, usually Python 3.10/3.11.
- Kept `RVC_OPTIONAL_PIP_SPEC` for advanced custom optional dependency lists.
- Optional RVC dependency failures are written to
  `Contents/Resources/voice-optional-dependency-warnings.txt` instead of being
  mixed with required dependency warnings.
- RVC runtime `requirements.txt` is filtered before install so `fairseq` entries
  from upstream forks are skipped by default.
- The filtered requirements file is preserved as
  `Contents/Resources/Voice/rvc-requirements.filtered.txt` for debugging.

## Why

Fairseq is a fragile legacy dependency on newer macOS/Python combinations. It
should never block packaging, code signing, or app bundle creation.

## Explicit opt-in

```bash
RVC_TRY_FAIRSEQ=1 PYTHON_BIN=/path/to/python3.10 ./build.sh
```

or:

```bash
RVC_OPTIONAL_PIP_SPEC="fairseq" PYTHON_BIN=/path/to/python3.10 ./build.sh
```

## Untouched

- Code-signing logic
- Claude's recording fixes
- Splice MCP/download/preview
- Serum / Serum 2 / hosted plug-in fixes
- AU hosting
- Demucs/stems
- Piano Roll
- Browser drag/drop
- Monitor modes
- Mixer FX
- Warp controls
- Metronome/count-in
