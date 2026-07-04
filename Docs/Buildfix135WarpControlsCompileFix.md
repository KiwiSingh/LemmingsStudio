# Buildfix135 — Warp Controls Compile Fix

This buildfix fixes a SwiftUI type-checker regression introduced by the clip-level warp controls.

## Fix

- Split `AudioClipWarpControls` in `ProDAWShell.swift` into smaller computed view sections.
- Replaced the inline interpolated `Button("Detected \(Int(detected))")` expression with a small view-builder helper and precomputed string.
- Preserved the buildfix134 behavior: Warp toggle, Warp Mode picker, manual Clip BPM, Apply, ½, ×2, and reset-to-detected tempo.

## Untouched

Splice MCP/download/preview, Sound Agent, Demucs/stems, AU hosting, Piano Roll, browser drag/drop, mic recording/input devices, monitor modes, Mixer FX, and metronome/count-in timing were not touched.
