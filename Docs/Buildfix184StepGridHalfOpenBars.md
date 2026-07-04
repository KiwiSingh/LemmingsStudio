# Buildfix184 — Step Sequencer / Arrangement bar-boundary fix

## Problem
Printed or extended Step Sequencer clips could contain an extra hit exactly at the right edge of the clip. A simple one-bar EDM beat with a kick on step 0 could therefore produce a stray kick at the end of the printed/extended clip.

## Cause
`sequencerClipNotes(from:startBeat:endBeat:)` rendered while `beat < endBeat + 0.0001`. That made the render range closed-ish instead of half-open. For a one-bar 16-step pattern ending at beat 4.0, the loop rendered beat 4.0, wrapped it back to step 0, and appended a kick at the clip tail.

## Fix
Step Sequencer prints now render as a half-open musical range: `[startBeat, endBeat)`. The first step at the clip start is included, but the boundary at the clip end is excluded. This keeps bar downbeats aligned to the beginning of the next bar instead of being treated as a late hit in the previous bar.

## Files changed
- `Sources/LemmingsStudio/App/App.swift`
