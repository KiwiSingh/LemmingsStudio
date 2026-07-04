# Buildfix108 — Ableton-style clip drag between tracks

This pass fixes the buildfix107 interpretation of "move clips between tracks".
The context-menu Move to Track command remains, but clips can now also be moved
by dragging them vertically across Arrangement lanes.

## Behavior

- Drag a MIDI clip left/right to move it in time as before.
- While dragging, move the pointer vertically over another lane to choose the
  destination track.
- The destination lane is highlighted while hovering.
- Release the mouse to move the clip to that track.
- Moving a MIDI clip onto an audio track converts the destination to a MIDI /
  instrument-style track before inserting the clip.
- Moving an audio clip onto a MIDI/instrument track converts the destination to
  an audio track before inserting the clip.
- Horizontal fine-drag behavior is preserved: hold Option or Shift for smaller
  time movement.

## Scope

Changed file:

- `Sources/LemmingsStudio/Views/Arrangement.swift`

No Splice, Sound Agent, AU hosting, metronome, count-in, MIDI input, or audio
engine code was touched.
