# Buildfix203 — Oscillatron + LemmingBass are real instruments again

## Problem
Oscillatron and LemmingBass were present in the browser/device registry, but adding them through the normal device path could append them as transparent insert-style rack devices instead of making the track's live generator become the intended built-in instrument. That made them feel stubbed even though track-level instrument classes existed.

## Fix
- Rebuilt Oscillatron as an explicit 3-oscillator instrument:
  - Osc 1 saw
  - Osc 2 square
  - Osc 3 triangle/exotic interval oscillator
  - Sub oscillator
  - moving “exotic lemming shape” fold/saturation curve
  - filter, ADSR, pitch bend, and automatable controls
- Rebuilt LemmingBass as a BooBass-style mono bass instrument:
  - sine/shaped-square blend
  - sub oscillator
  - punch transient
  - low-pass filter
  - drive stage
  - tight envelope and pitch bend
  - automatable controls
- Adding instrument-class devices from the browser now loads/replaces the selected track's built-in instrument instead of inserting a transparent audio effect.
- Instrument devices are blocked from clip inserts, groups, and return buses with a clear status message.
- Drag/drop or mixer insertion of built-in instruments routes through the same track-instrument loader.

## Verification
Ran Swift parse checks across the full `Sources/LemmingsStudio` tree successfully.
