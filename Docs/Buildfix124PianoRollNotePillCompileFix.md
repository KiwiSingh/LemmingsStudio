# Buildfix124 — Piano Roll Note Pill Compile Fix

## Problem

Buildfix123 still failed to compile on Xcode beta because the Piano Roll note rendering chain was too complex for Swift's type checker:

```text
PianoRoll.swift:177:17: error: the compiler is unable to type-check this expression in reasonable time
```

The failing expression was the inline `RoundedRectangle` note view inside the `ForEach(clip.notes)` body.

## Fix

- Extracted the inline note rectangle view into a small `PianoRollNotePill` view.
- Precomputed note geometry/color values before constructing the pill.
- Kept click selection, Shift/Cmd additive selection, context-menu delete, and desktop-style marquee selection behavior intact.

## Scope

Touched only:

- `Sources/LemmingsStudio/Views/PianoRoll.swift`
- `Docs/Buildfix124PianoRollNotePillCompileFix.md`

No Splice, Sound Agent, Demucs, AU hosting, Arrangement, Mixer, metronome/count-in, or stem-splitting code was changed.
