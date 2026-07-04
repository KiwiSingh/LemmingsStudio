# Buildfix183 — Step Sequencer / Arrangement Isolation

## Problem
Buildfix181/182 fixed Arrangement doubling too aggressively. Printing or cleaning generated Step Sequencer clips could disable the source Step Sequencer (`source.useStepSequencer = false`) or treat a selected Arrangement clip as generated sequencer state. Deleting Arrangement material could therefore make the Step Sequencer appear silent.

## Fix
- Printing to Arrangement is now a non-destructive copy operation.
- The source track keeps `useStepSequencer = true` after print.
- Generated-preview cleanup only removes recognized preview/generated clips.
- Cleanup no longer empties notes, deactivates user clips, or mutates ordinary Arrangement material.
- Selection is no longer used as proof that a clip is generated.
- `refreshSelectedGeneratedClipIfNeeded` now refuses to rewrite a selected clip unless it is actually recognized as generated/preview material.

## Expected behavior
- Delete a printed clip in Arrangement: the Step Sequencer grid still plays when you return to Step Sequencer view.
- Delete/move/edit Arrangement clips: no Step Sequencer lanes, pattern cells, sample/plugin assignments, or live sequencer state are modified.
- Arrangement playback still avoids live/grid doubling by using Arrangement playback scope and isolated printed tracks.
