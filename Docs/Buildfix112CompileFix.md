# Buildfix112 Compile Fix

Fixes two build regressions reported from Xcode:

- `StemSplitter.isAvailable` no longer uses `await` inside a chained `||` expression. Swift 5/Xcode 27 rejects async calls on the RHS of non-assignment operators/autoclosure contexts, so availability checks are now explicit early returns.
- `ArrangementView` no longer references the private `LSTheme` enum from `ProDAWShell.swift`; the drop-zone fill now uses an equivalent local `Color`.

No Splice, Sound Agent, AU hosting, metronome, MIDI, or stem backend behavior was intentionally changed beyond making the existing stem backend availability checks compile.
