# Buildfix175 — Metronome Sync + Trackpad Zoom

## Scope

This buildfix addresses two video-recording blockers reported after buildfix174:

1. The audible metronome could feel late against printed Step Sequencer / Arrangement MIDI playback.
2. Trackpad zoom gestures in Arrangement View were not wired up.

## Metronome timing fix

The current live MIDI scheduler triggers any notes that fall inside the current CoreAudio render quantum at the start of that quantum. That is how printed Step Sequencer clips currently play. The metronome, however, was rendered sample-perfect inside its own source node. That meant a MIDI note that fell later in the buffer could be heard at the beginning of the buffer while the metronome click remained at the exact beat position, making the click sound late relative to the printed beat.

The metronome renderer now mirrors the same render-quantum scheduling behavior used by the live MIDI scheduler: if a beat boundary falls inside the current block, the click is pulled to frame zero of the block and the later duplicate click for that same boundary is suppressed.

This keeps the audible click locked with Arrangement / printed Step Sequencer playback until the MIDI engine grows fully sample-accurate note scheduling.

## Trackpad zoom

Arrangement View now attaches a simultaneous `MagnificationGesture` to the timeline canvas. Pinch zoom on a Mac trackpad adjusts horizontal zoom (`pxPerBeat`) directly, with guardrails so the timeline cannot collapse too far or explode to absurd width.

## Files changed

- `Sources/LemmingsStudio/Audio/AudioEngine.swift`
- `Sources/LemmingsStudio/Views/Arrangement.swift`
- `Docs/Buildfix175MetronomeSyncTrackpadZoom.md`

## Not touched

Stem splitter logic, stem backends, stem packaging, recording, code signing, Splice, Serum/Serum 2/plugin fixes, AU hosting, RVC/build.sh, export, mixer clipping, warp controls, Finder import, MIDI learn, automation point editing, User Library scanning, Windows port scaffolding.
