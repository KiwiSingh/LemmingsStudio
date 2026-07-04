# Buildfix 187 – Audio Clip Gain + Pitch Inspector

## Goal
When a user selects an audio clip in Arrangement, the clip should have its own non-destructive gain and pitch controls independent of track volume, master volume, or project settings.

## Changes
- Added clip-level `gainDB`, `pitchSemitones`, and `pitchCents` fields to `AudioClip`.
- Added computed render helpers:
  - `gainLinear`
  - `pitchRatio`
- Persisted the new fields in `AudioClipDoc` so saved projects keep clip gain/pitch settings.
- Copied the new fields through duplicate, copy/paste, track duplicate, split, and cloned audio-clip flows.
- Updated audio rendering so clip gain/pitch are applied at render time before clip insert FX.
- Added a **Clip Gain / Pitch** panel in the Clip inspector when an audio clip is selected:
  - Gain slider in dB
  - Semitone coarse pitch control
  - Cent fine pitch control
  - Reset button

## Behavior
- Clip gain is independent from track volume and master/project gain.
- Pitch semitones and cents combine into one pitch ratio.
- Looping audio clips use the pitch-adjusted source duration so loop wrap points remain musical instead of leaving silence after pitch-up changes.
- Existing projects load with defaults: `0 dB`, `0 semitones`, `0 cents`.
