# Buildfix133 — Audio recording UX/layout + theme propagation

Fixes three issues found after buildfix132:

- Audio input channel picker could visually spill past the track header and overlap the Arrangement timeline.
- Pressing Record gave no immediate arrangement feedback, making audio recording look like it was doing nothing.
- Liquid Glass themes needed to propagate more consistently into the whole shell/workspace instead of leaving Arrangement/sidebar-adjacent surfaces feeling like old flat panels.

## Changes

### Arrangement track header layout

- Wider Arrangement track header column so Monitor / Input Device / Input Channel controls fit inside the header.
- The channel picker no longer overlaps the timeline lane area.
- Arrangement grid/header/drop-zone colors now use `LSTheme` palette values.

### Audio recording feedback

- Starting audio recording now immediately creates a provisional `AudioClip` on the target audio track.
- The provisional clip is named using the selected device and input channel.
- While recording, its arrangement length grows from the captured sample count.
- Stopping recording fills that same provisional clip with captured samples.
- If no samples were captured, the empty take remains visible and the recorder reports a device/channel/permission warning instead of silently doing nothing.
- Stop commits to the original active recording track, even if selection changes during the take.

### Broader Liquid Glass theme application

- Root content now applies the selected theme as tint/accent/foreground context.
- Theme changes force the shell to refresh so browser/workspace/sidebar surfaces pick up the active theme.
- Arrangement view now uses themed background, grid, focus, record, and dim colors.

## Untouched

Splice MCP/download/preview, Sound Agent, Demucs/stems, AU hosting, Piano Roll, browser drag/drop logic, Mixer FX routing, and metronome/count-in timing were not changed.
