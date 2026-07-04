# LemmingsStudio buildfix231

Focused Windows VST3 follow-up after buildfix230.

- Added native helper PCM request/response path:
  - `renderMidi`
  - `processAudio`
- Added request IDs and synchronous response handling to `Vst3NativeHostBridge`.
- Changed native helper JSON output to compact JSONL so the managed bridge can parse it reliably.
- Windows MIDI clip rendering now attempts VST3 instrument rendering through the native helper.
- Windows device-chain rendering now attempts VST3 effect processing through the native helper.
- If native VST3 rendering fails, playback/export falls back to dry/local rendering rather than crashing.

Validation caveat: this environment cannot compile .NET or JUCE/CMake, so test on the Windows VM with `-RequireNativeVst3Host`.
