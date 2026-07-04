# Buildfix232 — Windows VST3 Parameters, State, Automation, Latency

This pass extends the buildfix230/231 native Windows VST3 helper beyond editor/MIDI/PCM transport.

## Added

- Native helper JSONL ops:
  - `getParameters`
  - `setParameter`
  - `getState`
  - `setState`
  - `getInfo`
- JUCE generic editor fallback for plug-ins with no custom editor.
- Plug-in parameter enumeration with normalized values, names, display text, and automation flags.
- Plug-in state persistence as base64 state blobs stored in project `DeviceSlot.PluginStateBase64`.
- Bus/latency metadata stored on `DeviceSlot`.
- Device Rack buttons:
  - `Host` loads/restores a VST3 slot.
  - `Params` refreshes native parameter metadata.
  - `State` explicitly snapshots plug-in state.
- VST3 rack sliders now call `setParameter` live.
- MIDI Learn works on discovered VST3 parameter keys.
- Automation lanes are generated for discovered VST3 parameters and pushed to the native helper during render.
- First-pass latency compensation for VST3 effect processing shifts processed PCM left by reported latency samples.

## Still intentionally not claimed as complete

- Sample-accurate parameter automation inside long render blocks is not done; this pass applies parameter automation at clip boundaries.
- Shared-memory PCM transport is still a future optimization. JSON/base64 remains the compatibility path.
- Multi-bus sidechain/aux layouts are reported but not yet fully routable from the C# engine.
- Plug-in preset browsers and program lists are not implemented yet.
