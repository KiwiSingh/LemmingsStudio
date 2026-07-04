# LemmingsStudio buildfix230

Windows VST3 native helper implementation pass.

- Added `Ports/Windows/native/LemmingsVst3Host`, a JUCE-based C++ VST3 host helper.
- Helper loads VST3 bundles/files, instantiates plug-ins, opens editor windows, and routes MIDI note/CC/panic events over JSONL IPC.
- Helper has a lightweight audio callback so VST3 instruments can sound during live MIDI testing.
- `build-installer.ps1` now attempts to build and bundle `LemmingsVst3Host.exe`.
- Added `-SkipNativeVst3Host`, `-RequireNativeVst3Host`, and `-NativeVst3HostPath` to Windows build scripts.
- Published app manifest now records whether `LemmingsVst3Host.exe` was bundled.
- Added docs in `Docs/Buildfix230WindowsNativeVst3Host.md`.

Honest remaining gap: full project offline render/export through VST3 still needs a dedicated PCM block streaming IPC pass.
