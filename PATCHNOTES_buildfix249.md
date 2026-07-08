# buildfix249 — visionOS AUv3 discovery and hosting

## Summary

This build adds the first native Audio Unit hosting layer to the visionOS port.

## Added

- Native AU discovery through `AVAudioUnitComponentManager`.
- Discovery of instrument, generator, effect, and music-effect Audio Units.
- Asynchronous `AVAudioUnit.instantiate` loading.
- Real graph insertion into `VisionAudioEngine`:
  - instrument/generator output feeds the shared mixer,
  - effect units insert between the shared mixer and stock EQ chain.
- Live CoreMIDI forwarding to hosted AU instruments for notes, CC, and pitch bend.
- Parameter-tree enumeration through `AUAudioUnit.parameterTree`.
- Generic spatial parameter control surface.
- Optional plug-in-provided custom UI hosting.
- `fullStateForDocument` capture and project-level state persistence.
- Restore-on-project-open when the same AU component is available.
- Clear missing-AU status when a saved project references an unavailable unit.
- New Plug-in Browser and Plug-in Controls windows.

## Current scope

The first pass intentionally supports one active native AU slot at a time. This establishes a real, testable host and state model before implementing a multi-slot device rack on visionOS.

## Validation note

Source structure and shell/plist integrity were checked in the build container. A real compile/runtime test still requires Xcode with the visionOS SDK and at least one compatible AUv3 installed in the simulator/device environment.
