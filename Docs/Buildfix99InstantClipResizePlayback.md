# Buildfix99 — Instant Arrangement Clip Resize During Playback

Scope: Arrangement View only. Splice, AI, AU hosting, metronome, and recording paths are untouched.

## Problem

Edge-resizing clips in Arrangement View still felt slow and non-Ableton-like. The previous implementation still did expensive work inside `DragGesture.onChanged`, including arrangement-length mutation and MIDI loop materialization during each drag frame. That made side-pulls feel laggy, especially for looped MIDI clips.

Playback edits were also too conservative: ending a drag could rebuild the engine even when transport was running, which is the opposite of how DAW timeline edits should feel.

## Fix

- Clip resize gestures now use `minimumDistance: 0` for immediate edge response.
- Drag updates run inside a no-animation SwiftUI transaction.
- Arrangement length expansion is committed once at drag end, not on every mouse move.
- Looped MIDI note materialization is deferred until drag end instead of recalculating the repeated note array every frame.
- Engine rebuild is skipped while playback is active. The render path reads the observable clip objects, so length/start changes are already live during playback.
- Existing stopped-transport rebuild behavior remains, so non-live caches are still refreshed when the edit completes.

## Files changed

- `Sources/LemmingsStudio/Views/Arrangement.swift`
