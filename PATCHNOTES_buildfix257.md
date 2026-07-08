# LemmingsStudio buildfix257 — visionOS Metadata Scanner + Shared Backend Protocol

## Scope

Buildfix257 continues the sideload-first **Gojira Compatibility Lab** from buildfix256, but keeps it safe by moving the next layer to metadata-only scanning and backend planning. No macOS or Windows app paths are intentionally changed.

## Added

- `VisionPluginBackendProtocol.swift`
  - Adds a shared backend protocol seam for all visionOS plug-in routes.
  - Normalizes backend capabilities for:
    - Native AUv3
    - Mac Companion
    - Experimental macOS `.component`
    - Experimental Wine ARM64
    - Experimental Wine + FEX
  - Adds `VisionPluginBackendPlan` so every candidate can be converted into a dry-run execution plan before runtime work begins.

- `VisionPluginMetadataScanner.swift`
  - Adds metadata-only candidate scanning.
  - Reads nearby `Info.plist` data when available.
  - Classifies `.appex`, `.component`, `.vst3`, `.clap`, and `.dll` candidates.
  - Records architecture/import/framework hints without executing plug-in code.
  - Flags obvious desktop-only assumptions such as AppKit/NSView-style metadata.

- Compatibility Lab UI updates
  - New Shared Backend Protocol capability table.
  - New Metadata Scanner Reports section.
  - New Backend Plans section.
  - Candidate actions now include:
    - Scan Metadata
    - Backend Plan
    - Metadata Dry Run
    - Route to Mac Companion

## Safety / Runtime Notes

- This patch does **not** call `dlopen`, `Bundle.load`, `Process`, Wine, FEX, or any plug-in binary.
- All local chaos paths remain dry-run / metadata-only.
- Real execution remains gated behind future sideload/dev-mode runtime work.

## Next steps for full macOS parity

1. Add real Mach-O and PE magic-byte parsers so scanner reports can identify `arm64`, `x86_64`, and Windows ARM64/x64 slices accurately.
2. Complete the Mac Companion desktop plug-in path first, because it is the most realistic bridge for desktop AU/VST3/CLAP parity.
3. Add a shared parameter tree protocol so native AUv3, Mac Companion, Wine, and Wine+FEX all expose the same automation surface.
4. Add a shared editor-surface protocol for streamed/spatial plug-in UIs.
5. Once plug-in compatibility is sane, return to core DAW parity: mixer routing, automation lanes, offline bounce/export, recording, and arrangement editing.

## Recommended buildfix258 target

Buildfix258 should implement the real scanner backend:

- Mach-O header parsing
- PE header parsing
- bundle resource inventory
- import/dependency hints
- risk scoring
- compatibility badges in the Plugin Browser and Compatibility Lab
