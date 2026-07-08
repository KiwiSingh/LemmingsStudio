# LemmingsStudio buildfix258 — visionOS plugin parity contracts

## Added

- Real metadata-only Mach-O / PE header parser for the visionOS Compatibility Lab.
- Header parsing button and binary report section for `.component`, `.vst3`, `.clap`, `.appex`, and `.dll` candidates.
- Mac Companion plug-in parity contract models: discovery descriptors, instances, parameters, editor surfaces, latency metadata, and command previews.
- Shared parameter automation parity state for native AUv3, Mac Companion, and future Wine/FEX backends.
- Streamed/spatial editor surface model for desktop plug-ins hosted by the Mac Companion.
- Bounce/export parity dry-run model covering master, stems, selected track, and selected clip scopes.
- New visionOS **Plugin Parity** window to inspect Companion inventory, instantiate previews, expose parameters, and prepare export dry-runs.

## Safety / architecture

- The binary parser does not `dlopen`, `Bundle.load`, spawn Wine, or execute third-party plug-in code.
- Wine/FEX and local macOS component execution are still gated behind dry-run planning.
- Mac Companion remains the shippable desktop plug-in path while the Gojira local runtime matures.

## Next steps for full macOS parity

1. Replace the demo Mac Companion inventory with real `/plugins`, `/instantiate`, `/parameters`, `/editor`, and `/audio-return` endpoints.
2. Smoke-test Windows ARM64 Wine with a no-editor metadata probe before attempting audio or GUI.
3. Wire streamed editor input round-tripping: gaze, pinch, pointer, keyboard, and MIDI learn.
4. Attach bounce/export dry-runs to the real VisionAudioEngine offline renderer and Companion audio return capture.
5. Complete Arrangement automation lane UI and clip take/recording parity.
6. Continue the Wine+FEX chaos path only after PE/Mach-O reports classify a candidate as safe enough for controlled sideload testing.

## MLX stack note

- Keep MLX local-first but route heavy VLMs through the Mac Companion when headset thermal/memory limits get spicy.
- Best near-term split: small on-device text/control model on visionOS; Qwen2.5-VL-style multimodal model on Mac Companion for screenshots/plugin UI reasoning.
