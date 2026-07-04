# Buildfix 157 — Finder Drop / Armed Track Audio Import Regression

## Problem

Dropping/importing audio could throw an opaque CoreAudio/AVFAudio error while a
track was armed for recording:

```text
com.apple.coreaudio.avfaudio error 2003334207
```

This was especially visible after Finder drag/drop support because SwiftUI's
`NSItemProvider.loadFileRepresentation` may provide a temporary file that is only
safe to use during the provider callback. If the app hopped back to the main
thread and decoded later, that temporary URL could already be invalid. Armed
tracks also keep input hardware warm, making the timing-sensitive failure easier
to reproduce.

## Fix

- Finder-provided file representations are now copied immediately into a stable
  temporary `LemmingsStudioFinderDrops` location before the import is dispatched
  to the main actor.
- Audio import now starts security-scoped access before reading.
- Audio import now retries with an explicit Float32/non-interleaved
  `AVAudioFile` decode before surfacing an error.
- The user-facing failure message is no longer just the raw opaque AVFAudio code.

## Scope guard

No changes were made to recording, code signing, Splice, Serum/Serum 2/plugin
hosting, AU hosting, RVC/build.sh, Demucs packaging, export, mixer clipping,
warp controls, or metronome/count-in.
