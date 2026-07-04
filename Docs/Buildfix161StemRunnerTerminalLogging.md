# Buildfix161 — Stem Runner Terminal Logging

## Why

Launching LemmingsStudio from Terminal produced an empty log while stem splitting failures were only visible inside the popup. That made it annoying to capture the exact Demucs / MLX / Core ML failure point.

## What changed

- `StemSplitter` now mirrors stem-split diagnostics to:
  - `stderr`, so launching `LemmingsStudio.app/Contents/MacOS/LemmingsStudio` from Terminal shows live logs.
  - `NSLog`, so Console.app / unified logs can also show the messages.
  - a persistent file, defaulting to `~/Desktop/lemmingsstudio-stem-debug.log` when the Desktop exists, otherwise `/tmp/lemmingsstudio-stem-debug.log`.
- You can override the file path with:

```bash
LS_STEM_LOG_FILE="$HOME/Desktop/my-stem-log.txt" \
/Applications/LemmingsStudio.app/Contents/MacOS/LemmingsStudio
```

## Logged details

Each stem split now logs:

- selected input path
- requested backend
- effective backend/model after guardrails
- requested stems
- auto backend order
- fallback decisions
- exact subprocess command
- output directory
- backend stdout/stderr as it arrives
- exit status
- failure summary
- successful stem names

## Scope guard

Only stem-runner diagnostics changed. No recording, code signing, Splice, Serum, AU hosting, RVC/build.sh, Demucs packaging, export, mixer, warp, metronome, or Finder import logic was changed.
