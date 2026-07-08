# LemmingsStudio buildfix264 — Integrated Host Mode launch parity pass

Public version numbers remain unchanged:

- macOS: v2.0
- Windows: v2.0
- visionOS: v1.0

## Integrated Mac Host Mode

The existing macOS LemmingsStudio app is the host. No separate companion application is required.

Buildfix264 extends the already-live Bonjour bridge with:

- Host Mode menu commands on macOS: Start, Stop, and Status/Pairing Code.
- Protocol version 2 handshake.
- AU enumeration and remote instantiation.
- Parameter tree synchronization and remote parameter writes.
- MIDI event transport.
- plugin state request/restore.
- live stereo audio return.
- streamed plug-in editor JPEG frames.
- visionOS drag/touch input returned to the hidden macOS editor surface.
- tempo-aware Mac-side offline WAV rendering for the active hosted instance.
- visionOS-side render reception and local WAV persistence.

## visionOS automation parity

- Mixer volume and pan automation lane exposure.
- Mac Host Mode parameter automation targeting.
- Add/remove automation points.
- linear and hold interpolation.
- playback-time automation application.
- dedicated Automation Lanes window.

## visionOS recording/take parity

- Persistent take folder data model.
- recording output automatically appended as a take.
- active take folder selection.
- comp-take selection.
- dedicated Takes & Comping window.
- recording decisions added to Living Project Memory.

This is not yet full macOS-style region comping. Punch in/out, pre-roll, comp-region slicing, and swipe-comp gestures remain follow-up work.

## Gojira Compatibility Lab

The Wine ARM64 path is no longer dry-run-only. Buildfix264 adds an opt-in sideload-only `posix_spawn` process probe that:

- resolves a staged Wine ARM64 runtime inside the app container,
- validates the Wine executable, prefix, candidate plug-in, and `vsthost-probe.exe`,
- launches the runtime process,
- waits for and records the exit status,
- reports the result inside Compatibility Lab.

No Wine runtime binaries are distributed in this source archive.

## MLX runtime

A conditional `VisionMLXLocalRuntime` adapter is included. When MLX Swift LM products are linked into the visionOS build profile it can load a configured VLM repository and run local inference; otherwise it fails explicitly and leaves the stable build unaffected.

The adapter follows the MLX Swift LM model-container/generation architecture and does not allow AI text to mutate the project directly. Tool execution remains confirmation-gated.

## Validation performed in this environment

- Swift parser validation passed for the new/modified Host Mode, automation, Wine probe, MLX adapter, and visionOS UI sources.
- `Ports/visionOS/build-visionos.sh` passes shell syntax validation.
- Public platform version metadata remains macOS/Windows v2.0 and visionOS v1.0.

## Requires macOS/Xcode/hardware validation before public binary upload

- compile and archive all Apple targets in Xcode,
- sign/export the visionOS hardware IPA,
- build the visionOS Simulator ZIP,
- verify editor streaming against real third-party AU editors,
- measure local-network editor and audio latency,
- verify manual rendering behavior for specific Audio Units,
- validate opt-in MLX Swift LM package resolution and model inference on Vision Pro hardware,
- test the Wine ARM64 probe only with a deliberately staged compatible runtime.

## Next steps for full macOS parity

1. Project-level master and stem bounce through Host Mode.
2. Full comp-region editing, punch, count-in, and pre-roll.
3. Write/Touch/Latch automation modes and persisted automation serialization.
4. Authenticated Splice MCP preview/download workflow.
5. Hardware validation and performance tuning of local MLX VLM inference.
6. Wine ARM64 loader bring-up and first real VST3 host-probe result.
7. Final parity audit across Arrangement, Mixer, Recording, Export, Plug-ins, AI, and project persistence.
