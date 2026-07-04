# Buildfix159 — Stem backend diagnostics + Auto fallback

Scope guard: this buildfix only touches stem splitter backend selection/diagnostics.
It does not touch recording, code signing, Splice, Serum/Serum 2/plugin hosting,
AU hosting, RVC/build.sh, export, mixer clipping, warp controls, or metronome/count-in.

## Fixed

- `Separation failed: stem backend exit 1` no longer hides the useful backend error.
- StemSplitter now captures stdout/stderr from Demucs/MLX/Core ML and includes the
  command + backend output tail in the error message.
- Auto backend mode now genuinely retries available backends instead of selecting one
  backend and dying there.
- For `htdemucs_6s`, Auto prefers official Demucs first because MLX/Core ML runners
  commonly expose only the 4-stem HTDemucs path.
- If a backend exits successfully but no requested stem files are found, the error now
  says which output folders were searched instead of pretending the split succeeded.
- Progress is nudged at start/end so the popup does not look dead while the backend is
  booting or completing.

## Why

The popover/start button fix made the UI flow correct, but Auto still resolved to the
first backend that appeared importable. On Apple Silicon that can be MLX/Core ML, and
those runners may exit when asked for `htdemucs_6s`. The old code reported only
`stem backend exit 1`, which made debugging impossible.

Buildfix159 keeps the full backend setup, but makes Auto resilient and makes explicit
backend failures actionable.
