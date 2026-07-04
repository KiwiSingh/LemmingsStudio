# Buildfix122 — Piano Roll Desktop-Style Marquee Selection

## Scope
Changed only the Piano Roll selection interaction. No Splice, Sound Agent, AU hosting, Demucs, mixer, metronome/count-in, Arrangement, or MIDI-controller code was touched.

## What changed
- Empty-grid mouse drag now behaves like desktop icon selection: click, hold, drag a rectangle across notes, release to select intersecting notes.
- The marquee gesture now lives on the Piano Roll grid background instead of the whole editor container, so note clicks continue to select notes normally.
- Tiny mouse movement is treated as a click-to-add-note rather than creating an accidental zero-size marquee.
- Shift/Cmd during marquee selection still adds to the existing selection.
- Piano Roll focus is set as soon as the drag begins so context-aware undo/redo continues to prefer note edits.

## Why
The previous build exposed selection commands and a marquee rectangle, but the interaction did not match the expected desktop/Ableton-style mouse selection workflow closely enough.
