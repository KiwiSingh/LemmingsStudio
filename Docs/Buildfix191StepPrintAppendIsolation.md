# Buildfix191 — Step Sequencer Print Append + Playback Isolation

## Fixes

- Step Sequencer print now appends to an existing compatible print track, or to the explicitly selected compatible Arrangement track, instead of always making/replacing a print lane.
- Fresh prints start at the later of the playhead or the selected/remembered print track's end, snapped to the Arrangement grid.
- Printed step notes are clipped strictly to the print clip's half-open range so a note from the previous print cannot bleed into the next adjacent print.
- MIDI edge-loop materialization no longer forces a minimum note length across loop boundaries.
- Step Sequencer playback scope now hard-mutes every non-live-step track, including frozen bounces, audio clips, hosted instruments, and lingering AU/plugin output.

## User-facing behavior

- Print 1 followed by Print 2 should produce adjacent Arrangement clips with no stray hat/kick from the previous print.
- Selecting an Arrangement track before printing uses that track as the destination.
- If no compatible track is selected, subsequent prints append to the remembered print lane from the same Step Sequencer source.
- Switching to Step Sequencer view isolates the live grid and does not play Arrangement material.
