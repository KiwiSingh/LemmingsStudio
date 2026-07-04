# Buildfix 134 — Warp Mode + Manual Clip Tempo Override

## Why

Warp could be enabled on imported audio, but the selected-clip workflow did not expose the actual warp mode prominently enough, and detected BPM could be wrong with no obvious manual override.

## Changed

- Added selected audio clip warp controls to the Detail Deck.
- Added a per-clip Warp toggle.
- Added a per-clip Warp Mode picker.
- Added a manual Clip BPM field with Apply / half-tempo / double-tempo helpers.
- Added a Detected BPM reset button when a detected tempo exists.
- Added context-menu helpers for Clip Tempo.
- Preserved the chosen warp mode in project files.
- Added `manualTempoOverride` on `AudioClip` so manual BPM overrides are distinguishable from detected tempo.
- Updated the Studio warp panel to route through the same app-level warp/tempo functions.

## Notes

- Manual Clip BPM overrides the detected tempo used by the warp engine.
- The original detected BPM remains stored so the user can reset back to it.
- Existing projects still load: new project fields are optional where needed.
- This patch does not change the actual stretch algorithms.

## Not touched

Splice MCP/download/preview, Sound Agent, Demucs/stems, AU hosting, Piano Roll, browser drag/drop, mic recording/input devices, monitor modes, Mixer FX routing, and metronome/count-in timing were not changed.
