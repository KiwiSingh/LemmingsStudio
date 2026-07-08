# buildfix310 hotfix 1

- Fixes the visionOS compile failure in `VisionFloatingMIDIKeyboardView.swift` caused by the inline compact keyboard calling the removed legacy `SpatialPianoKey(note:isBlack:isActive:noteName:onPress:onRelease:)` initializer.
- Uses the current visual-only `SpatialPianoKey(isBlack:isActive:noteName:)` initializer.
- Restores note press/release behavior by attaching a zero-distance drag gesture around the compact key view.
- Preserves bf310 stock FX, universal automation, spatial gesture mapping, bf309 release plumbing, layered AppIcon, Xcode model staging, and unsigned IPA packaging.
