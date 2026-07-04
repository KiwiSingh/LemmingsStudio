# Buildfix123 — Piano Roll Modifier Compile Fix

Buildfix122 added desktop-style Piano Roll marquee selection, but used a non-existent SwiftUI environment key:

```swift
@Environment(\.eventModifiers)
```

On the current macOS/Xcode toolchain this fails to compile because there is no `eventModifiers` environment value in this app context.

Buildfix123 removes that invalid environment dependency and reads the active mouse modifier state from AppKit at the moment the click/drag gesture ends:

- Shift/Cmd click still toggles/adds note selection.
- Shift/Cmd marquee still adds to the current selection.
- Plain marquee replaces selection.
- Empty-grid click still adds a note.

No Sound Agent, Splice, Demucs, AU hosting, Arrangement, Mixer, metronome, or stem code was changed.
