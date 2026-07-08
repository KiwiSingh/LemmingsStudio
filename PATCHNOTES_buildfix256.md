# LemmingsStudio buildfix256 — visionOS Gojira Compatibility Lab

## Scope

buildfix256 is a visionOS-only sideload/dev-mode compatibility patch layered on top of buildfix255. macOS and Windows source paths are intentionally untouched.

## Added

- Added `VisionCompatibilityLabView`, a new visionOS window for experimental plugin compatibility work.
- Added `VisionGojiraCompatibilityRuntime.swift`, a sideload-first compatibility model for:
  - native AUv3 routing
  - Mac Companion fallback routing
  - experimental macOS `.component` metadata probes
  - experimental Wine ARM64 probes
  - experimental Wine + FEX x64 chaos probes
- Added a top-bar `Compatibility Lab` entry point.
- Added a new `compatibility-lab` window scene.
- Added plugin candidate classification for `.appex`, `.component`, `.vst3`, `.clap`, and `.dll` shapes.
- Added dry-run command previews instead of executing third-party plugin code.
- Added runtime root hints for staged Wine, FEX, and macOS component experiments.

## Why this exists

The visionOS build is targeting sideloading, so buildfix256 opens the door to more aggressive research than an App Store-safe build would allow. The compatibility lab intentionally separates stable plugin paths from cursed experimental paths:

1. Native AUv3 remains the preferred path when available.
2. Mac Companion remains the reliable desktop-plugin compatibility path.
3. Local macOS component loading, Wine, and Wine + FEX live behind a clearly marked Gojira lab surface.

## Safety/architecture guardrails

- This patch does not make Wine, FEX, or macOS component loading mandatory.
- The lab currently performs classification and dry-run planning only.
- Third-party plugin code execution should come only after metadata-only scanners are implemented.
- The runtime is isolated under `Ports/visionOS/LemmingsStudioVision/Compatibility/`.
- Stable AUv3 hosting and Mac Companion bridge paths remain intact.

## Next steps for full macOS parity

1. Implement a metadata-only Mach-O/component scanner for macOS `.component` bundles.
2. Add a small VST3 metadata probe format that can run under Mac Companion first, then under Wine ARM64 later.
3. Define the shared `PluginBackend` surface for parameters, editor surface, audio return, MIDI input, and state save/restore.
4. Finish the Mac Companion route as the reliable path for desktop AU/VST3/CLAP.
5. Begin the first local Wine ARM64 smoke test using a harmless Windows ARM64 test plugin/host before attempting real commercial plugins.
6. Treat FEX-on-visionOS as a separate research spike because FEX assumes Linux userspace; the likely work is a Darwin/visionOS backend or a very narrow translation shim.
7. After plugin compatibility stabilizes, continue with mixer routing parity, automation lanes, offline bounce/export, recording/comping, and deeper Splice MCP integration.
