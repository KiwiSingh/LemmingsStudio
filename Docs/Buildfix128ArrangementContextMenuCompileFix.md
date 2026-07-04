# Buildfix128ArrangementContextMenuCompileFix

Fixes the buildfix127 compile regression in `Arrangement.swift`.

## Problem

`trackContextMenu(_:)` returned `some View` but contained multiple statements/conditionals without `@ViewBuilder`, so Swift could not infer the opaque return type.

## Fix

Added `@ViewBuilder` to `trackContextMenu(_:)`.

## Touched files

- `Sources/LemmingsStudio/Views/Arrangement.swift`
- `Docs/Buildfix128ArrangementContextMenuCompileFix.md`

No Splice, Sound Agent, Demucs, AU hosting, Piano Roll, Mixer, metronome/count-in, or stem code was changed.
