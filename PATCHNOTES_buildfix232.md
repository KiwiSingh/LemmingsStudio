# Buildfix232 — Windows native VST3 parameter/state/automation pass

- Added native VST3 helper commands for parameter enumeration, setting normalized parameters, state save/restore, and latency/bus reporting.
- Added JUCE generic editor fallback when a plug-in has no custom editor window.
- Added C# bridge methods for `RefreshParameters`, `SetParameter`, `SaveState`, `RestoreState`, `RefreshInfo`, and stored-parameter replay.
- Added persistent VST3 metadata to `DeviceSlot`: state blob, latency, I/O channel counts, discovered parameters.
- Device Rack now exposes Host / Params / State controls for VST3 slots.
- VST3 rack sliders and MIDI Learn now send parameter changes to the native helper.
- Automation lanes are generated for discovered VST3 parameters and applied during render.
- VST3 effect latency is compensated with a first-pass sample shift on processed PCM.

Caveats: parameter automation is clip-boundary granularity in this pass; shared-memory PCM, full bus routing, sidechains, preset browsers and sample-accurate automation remain future VST3 work.
