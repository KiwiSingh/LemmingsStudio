# LemmingsStudio buildfix229

Focused Windows VST3/MIDI pass:

- Added `Vst3NativeHostBridge` app-side IPC boundary for a real native VST3 helper.
- Added host status logging and Tools → Start Native VST3 Host.
- VST3 device cards now include Host and Editor actions.
- Editor action tries native helper first, then external Carla/Element/custom bridge.
- MIDI live note-on/note-off/CC routing can now target the first enabled VST3 slot on the selected MIDI/instrument track.
- MIDI panic reaches the native host when available.
- Added documentation for the JSONL native host protocol and helper expectations.

Important: this is the host boundary and UI/MIDI routing pass, not the compiled Steinberg SDK helper itself. The app now exposes the missing helper honestly and is ready for the native C++ helper to be dropped in as `LemmingsVst3Host.exe`.
