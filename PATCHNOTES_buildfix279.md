# buildfix279 — visionOS third source compile hotfix

- Restores `VisionMLXModelPreset.recommendedUse` as computed preset guidance consumed by the Agent Panel.
- Unwraps the known-valid 48 kHz stereo `AVAudioFormat` before constructing `AVAudioSourceNode`.
- Keeps public versions unchanged: macOS 2.0, Windows 2.0, visionOS 1.0.
