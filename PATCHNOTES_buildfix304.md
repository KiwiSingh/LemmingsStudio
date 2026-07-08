# buildfix304 — visionOS export parity hardening

This build is visionOS-only and extends buildfix303.

## Export graph parity
- Replaced the earlier simplified master renderer with a shared offline graph based on `AVAudioEngine` manual rendering.
- Mirrors the live graph topology for the native stable path: main dry signal → EQ → Delay → Reverb → master.
- Mirrors Return A delay and Return B reverb routing, including project bus volume, pan, mute, and effect-mix values.
- Snapshots the currently configured live EQ/Delay/Reverb values before export.

## AUv3 offline rendering
- Saved AUv3 effect/other state can be instantiated in the offline manual-render graph ahead of the stock EQ/Delay/Reverb chain.
- Restores `fullStateForDocument` from project state before rendering.
- Instrument/generator AUv3 MIDI offline scheduling is not claimed here; this pass focuses on effect graph parity and preserves the native stock instrument render path.

## Automation-accurate export
- Mixer volume and pan automation are evaluated for every exported sample frame.
- Return A/B send automation is supported through `visionMixer` parameter IDs `send.return-a` and `send.return-b`.
- Existing Hold, Linear, Smooth, Exponential, and curve-handle behavior is reused by the offline evaluator.

## Stem modes
- Pre-Fader
- Post-Fader
- Post-FX

## Return bus export modes
- Bake Into Mix
- Separate Returns
- Bake + Separate
- Exclude Returns

Separate return export writes `Return-A` and `Return-B` files alongside stems.

## Progress and cancellation
- Progress state now reports phase, current track, track index/total, completed frames/total frames, and overall fraction.
- Cancellation is checked during track rendering, clip processing, automation application, offline FX chunks, stem iteration, and before file writing.
- Cancelled exports report a clean cancellation state instead of a generic failure.

## UI
- Added Stem Mode picker.
- Added Return Buses picker.
- Added detailed render progress panel.
- Added explicit Cancel button during rendering.
