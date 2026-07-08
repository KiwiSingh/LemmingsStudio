# Buildfix261 MLX Runtime + Floating MIDI Notes

This build adds the first real MLX runtime control surface and makes MIDI input more native to visionOS.

## MLX Runtime Core

The runtime is model-agnostic and runs in dry-run mode for now. It tracks:

- selected runtime backend
- selected local/hosted MLX model preset
- model cache/install status
- agent lane enablement
- semantic graph context budget
- tool scope per lane
- confirmation requirements

This is designed so the next pass can wire either MLX Swift, a local sidecar, or integrated macOS Host Mode without changing agent UI contracts.

## Floating MIDI Keyboard

The new floating keyboard gives visionOS users a built-in instrument input surface. It can play:

- local internal instruments
- hosted AUv3 instruments
- Mac-hosted desktop plugins over the bridge

The virtual keyboard uses the same `performMIDINoteOn` / `performMIDINoteOff` path as external MIDI.

## Bluetooth MIDI

`VisionMIDIManager` now exposes detected CoreMIDI source summaries and the floating keyboard window includes refresh/pairing controls. Bluetooth MIDI keyboards such as LUMI/ROLI devices should work once paired and exposed as CoreMIDI sources by the system.
