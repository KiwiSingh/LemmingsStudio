# Buildfix192 — Step Print Relative Half-Open Grid

Fixes a regression where adjacent Step Sequencer prints or stretched/looped clips could reintroduce a stray kick/hat at the clip tail.

## Root cause

The print renderer was mostly half-open, but it still derived the active step index from the absolute project beat using nearest rounding. Floating-point values near the right edge, such as `3.999999999`, could round to the next step number. For a 16-step pattern that wrapped back to step 0, causing a kick/hat from the next bar to appear at the end of the current clip.

## Fix

Step Sequencer prints now compute the rendered step index from the clip-relative beat using floor-based half-open indexing:

- clip range stays `[startBeat, endBeat)`
- pattern step 0 belongs to the clip start, not the previous clip end
- right-edge floating-point drift cannot wrap to step 0
- appended prints restart their pattern cleanly at their own clip start

## Files changed

- `Sources/LemmingsStudio/App/App.swift`
