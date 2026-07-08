# LemmingsStudio buildfix261 — MLX Runtime Core + visionOS MIDI Input Parity

## Focus
buildfix261 follows the earlier roadmap by starting the MLX Runtime Core while also closing a major visionOS performance-input gap: users can now play without a physical MIDI keyboard, and Bluetooth/CoreMIDI keyboard discovery is surfaced directly in the headset build.

## Added

### visionOS MLX Runtime Core
- Added `VisionMLXRuntimeCore.swift` as the local-first runtime planning layer.
- Added `VisionMLXRuntimeState` with runtime modes:
  - Disabled
  - Local MLX Swift
  - Local Sidecar
  - macOS Host Mode
  - Custom Endpoint
- Added model-install/cache metadata for quantized multimodal model presets.
- Added agent lanes for Arrangement, Mixer, Plugin, Spatial, Splice MCP, Compatibility Lab, and Learn.
- Added dry-run runtime planning using semantic graph node counts and scoped tool lists.
- Added safety gates for project graph context, screenshot context, and confirmation-required tool execution.
- Added a new `MLX Runtime` visionOS window.

### Floating MIDI Keyboard
- Added `VisionFloatingMIDIKeyboardView`.
- Added `VisionVirtualMIDIKeyboardState`.
- Added a floating multi-octave keyboard with:
  - base octave control
  - visible octave control
  - velocity control
  - latch mode
  - scale-assist placeholder
  - all-notes-off
- Virtual notes use the exact same dispatch path as physical MIDI:
  - local visionOS instrument engine
  - AUv3 host
  - desktop/macOS Host Mode bridge MIDI forwarding

### Bluetooth MIDI / LUMI-style keyboard support
- Extended `VisionMIDIManager` with detected source summaries.
- Added Bluetooth-likely classification for names containing Bluetooth/BT/LUMI/ROLI/Seaboard.
- Added source refresh UI in the new floating keyboard panel.
- Added an optional CoreAudioKit Bluetooth MIDI pairing sheet when available from the target SDK.
- Added `NSBluetoothAlwaysUsageDescription` to the visionOS Info.plist.

### App integration
- Added top-bar buttons for:
  - MIDI Keys
  - MLX Runtime
- Added status-bar MIDI source summary.
- Added new visionOS windows:
  - `floating-midi-keyboard`
  - `mlx-runtime`

## Kept untouched
- macOS plugin-hosting code remains intact.
- Windows port paths remain untouched.
- Existing visionOS Splice MCP, Compatibility Lab, Semantic Graph, splash/pre-splash, and plugin parity work remain additive.

## Notes
- The MLX runtime is still a planning/runtime-contract layer. It does not hard-link model binaries yet.
- Bluetooth MIDI on Apple platforms is ultimately CoreMIDI-based. Once a LUMI/ROLI-style keyboard is paired and visible to CoreMIDI, LemmingsStudio routes it like any other MIDI source.
- The floating keyboard intentionally forwards to the desktop bridge too, so the same headset UI can play Mac-hosted desktop plugins once Host Mode becomes live.

## Next steps for full macOS parity
1. Living Project Memory backed by a project-local store.
2. Integrated macOS Host Mode live endpoints inside the existing macOS LemmingsStudio app.
3. Real streamed plugin editor frames and gesture-to-plugin input routing.
4. Mixer routing, automation, and bounce/export parity.
5. Recording/take-folder parity.
6. First Wine ARM64 smoke test behind the Compatibility Lab dry-run gate.
