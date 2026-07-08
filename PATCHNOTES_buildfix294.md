# LemmingsStudio buildfix294

## visionOS compile hotfix

- Fixed `ButtonStyle` type inference failures in `VisionRootView.swift` and `VisionStepSequencerView.swift`.
- Replaced ternary `.buttonStyle(model.metronomeEnabled ? .borderedProminent : .bordered)` expressions with a stable `.bordered` style plus explicit `Color` tinting.
- Preserves visible metronome enabled/disabled state without relying on existential button-style inference.

## Validation

- 59 visionOS Swift files parse with `swiftc -parse`.
- visionOS shell scripts pass `bash -n`.
- asset catalog JSON files parse successfully.
