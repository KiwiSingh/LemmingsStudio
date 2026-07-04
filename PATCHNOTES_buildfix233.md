# LemmingsStudio buildfix233 — Windows VST3 completion pass

This pass tightens the Windows native VST3 host layer after buildfix232.

## Added

- File-backed PCM transport for large native VST3 render/process requests.
  - Inline JSON/base64 is still used for small buffers.
  - Larger buffers now use temporary `.f32` PCM files to avoid JSON payload blowups.
- Block-level VST3 automation events.
  - C# render/export builds VST3 automation events from project automation lanes.
  - Native helper applies parameter changes at their render block positions instead of only at clip boundaries.
- VST3 program/preset list bridge.
  - Native helper implements `getPrograms` and `setProgram`.
  - Windows Device Rack has a **Programs** button for VST3 slots.
- Extra VST3 info reporting.
  - Native helper reports editor availability, custom-editor support, bus layout text, input/output channel count, and latency.
  - Device slots persist the reported bus/editor metadata.
- Safer large render behavior.
  - If a VST3 call fails, the Windows audio engine still keeps the render dry/audible rather than crashing the project render.

## Still intentionally scoped

- Multi-bus/sidechain routing is reported and guarded, but complex sidechain routing is not yet exposed as a full UI matrix.
- Automation is block-level, not truly sample-accurate per individual sample.
- Native helper still needs to be built on Windows with Visual Studio Build Tools/CMake/JUCE.
