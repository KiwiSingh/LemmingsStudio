# Buildfix185 – MIDI Edge-Loop Uses Stable Half-Open Loop Unit

## Problem
Buildfix184 fixed Step Sequencer printing so printed clips use a half-open musical range `[startBeat, endBeat)`. That removed the stray step-0/downbeat kick at the printed clip tail.

However, dragging the right edge of a printed MIDI clip to loop it still used the clip's drag-start Arrangement length as the loop source. If the clip had already been stretched or if the drag source length drifted, the loop materializer could redefine the loop unit and reintroduce the same bad bar-boundary behavior. Duplicating the clip worked because it copied the original clip without redefining the loop source.

## Fix
`ArrangementView.loopMidiClip` now:

- preserves `clip.loopLengthBeats` as the canonical musical loop unit;
- uses the fallback drag-start length only when no valid loop unit exists;
- treats every repeated loop as a half-open range `[offset, offset + sourceLength)`;
- excludes notes exactly on the right edge of a loop iteration;
- clips note lengths to the current loop iteration so a note cannot bleed into the next repeat;
- writes the canonical source length back to `clip.loopLengthBeats` after materialization.

The right-edge MIDI resize gesture now calls `canonicalMidiLoopLength(for:fallback:)` instead of blindly replacing `loopLengthBeats` with `base.lengthBeats`.

## Expected Behavior
For a one-bar EDM beat with a kick on step 0:

- printing one bar does not add a stray kick at the end;
- dragging the clip edge out to 2, 4, or 8 bars repeats the kick only on the real bar starts;
- duplicate-clip and edge-loop now use the same bar-boundary semantics;
- repeated edge drags no longer promote the stretched length into the source loop length.
