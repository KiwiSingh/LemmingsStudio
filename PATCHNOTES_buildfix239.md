# LemmingsStudio buildfix239 — Windows Device Rack parity

## Scope
This pass focuses on the Windows Device Rack and chain-management UX.

## Added
- Drag-to-reorder devices in a track chain.
- Up/down reorder buttons as a precise fallback to drag operations.
- Per-device bypass state with visible On/Bypassed status.
- Clean delete flow that also removes automation lanes targeting the deleted device.
- Effect duplication with cloned parameters, MIDI mappings, VST3 metadata and saved plug-in state.
- Explicit visual classification:
  - Stock Instrument
  - Stock Effect
  - VST3 Instrument
  - VST3 Effect
- Instrument/effect chain rules:
  - stock instruments only on Instrument tracks;
  - one instrument per track;
  - instrument device remains first in the chain;
  - malformed projects remain recoverable: extra instruments are bypassed rather than silently deleted.
- VST3 editor, host, parameter refresh, state save and program selector grouped into the rack card.
- Visible MIDI Learn assignment status per parameter (channel + CC).
- Automation target creation directly from each parameter row.
- Duplicate automation target detection.
- Chain status indicator and invalid-chain warning.

## Notes
VST3 instrument/effect classification uses plug-in I/O metadata after the native host has queried it. Unknown, not-yet-hosted VST3 slots are conservatively treated as effects until metadata is available.

## Validation
This environment does not contain the Windows .NET SDK or Visual Studio toolchain, so the source was structurally reviewed but not compiled here.

Recommended Windows test command:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels -RequireNativeVst3Host
```
