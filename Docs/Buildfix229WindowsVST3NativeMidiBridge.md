# Buildfix 229 — Windows VST3 Native Host Boundary + MIDI Routing

This pass tightens the Windows VST3/MIDI architecture without pretending pure C# can host Steinberg VST3 plug-ins directly.

## Added

- `Vst3NativeHostBridge.cs`, the managed app-side IPC bridge for a real native helper named `LemmingsVst3Host.exe`.
- Native host status logging at app startup.
- Tools menu entry: **Start Native VST3 Host**.
- Device Rack VST3 cards now show the plug-in path and native host state.
- Device Rack VST3 cards now include a **Host** button that requests native-helper load.
- VST3 **Editor** now tries the native helper first, then falls back to Carla/Element/custom external bridge.
- MIDI / Hardware panel can route live MIDI notes and CCs to the first enabled VST3 slot on the selected target track.
- MIDI panic now also reaches the native VST3 helper when present.

## Helper contract

The app expects a helper process at either:

- `%APPDIR%\LemmingsVst3Host.exe`, or
- the path in `LEMMINGS_VST3_NATIVE_HOST`.

The protocol is JSON Lines over stdin/stdout:

```json
{"op":"ping"}
{"op":"load","slotId":"...","path":"C:\\...\\Plugin.vst3","name":"Serum 2"}
{"op":"openEditor","slotId":"...","parentHwnd":123456}
{"op":"noteOn","slotId":"...","channel":1,"note":60,"velocity":100}
{"op":"noteOff","slotId":"...","channel":1,"note":60}
{"op":"cc","slotId":"...","channel":1,"controller":74,"value":96}
{"op":"panic","slotId":"..."}
```

## Honest scope

This is the correct boundary for native Windows VST3 hosting, but this build does **not** yet include the compiled Steinberg SDK helper. Without the helper, VST3 slots still scan/save/open externally, and the UI reports the missing helper clearly. With the helper present, MIDI/editor requests route to it.
