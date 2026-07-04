# Buildfix119 — Sound Agent prose/family regression

Fixes the misleading Sound Agent success text for cases where the model returns prose instead of strict JSON, while LemmingsStudio successfully derives a deterministic sound-family recipe from the original prompt.

## Problem

For prompts like `Create me a rhodes-style piano`, the Sound Agent could apply many real AU automation events, but still report:

> AI returned prose instead of JSON; generated a conservative macro patch...

That was wrong. In this path the app often had a full prompt-derived Rhodes/electric-piano recipe, not a generic macro fallback.

## Fix

- The non-JSON path now reports whether parameters came from:
  - the user prompt,
  - the AI prose,
  - or both.
- It classifies the sound family in the status message: Rhodes/electric-piano, pluck, bass, supersaw, festival/progressive, etc.
- Macro fallback is now explicitly reported only when no prompt/prose recipe produced parameters.
- Rhodes/electric-piano recipe avoids sending redundant/unhelpful disabled toggle params such as Noise Off, Hyper Off, and unnecessary Delay block moves when the prompt did not ask for delay/echo.

## Notes

This does not change Splice, Demucs, Arrangement, metronome/count-in, mixer, or AU hosting lifecycle code.
