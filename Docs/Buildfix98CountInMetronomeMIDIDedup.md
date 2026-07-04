# Buildfix98 — Count-in Click + Live MIDI De-dup Regression Fix

## Scope

This buildfix is intentionally narrow. It only touches:

- `Sources/LemmingsStudio/Audio/AudioEngine.swift`
- `Sources/LemmingsStudio/App/App.swift`

Splice MCP/download/preview integration was not touched.

## Fixed: count-in muted the metronome

Buildfix96/97 started transport before the count-in and depended on the normal transport metronome path. That made the count-in fragile: the click could be marked silent, could begin at a fractional transport beat, and could also pre-roll the arrangement before recording had actually begun.

Buildfix98 adds a dedicated count-in click clock in `AudioEngine`:

- `startCountInClick(beats:tempo:)`
- `stopCountInClick()`
- `isCountInClicking`

During count-in, the metronome renders from this wall-clock click clock rather than from the project transport. Recording/transport begins only after the count-in has completed.

## Fixed: first record MIDI notes sounding multiple times

Buildfix98 adds an app-level live MIDI note de-dup guard keyed by:

- track ID
- MIDI channel
- routed note number

Duplicate note-ons for the same held note are ignored until the corresponding note-off arrives. This prevents AU synths such as Serum 2 from receiving repeated `noteOn` events from duplicate CoreMIDI endpoints, controller echo, or racey first-record/count-in startup while still recording only one logical MIDI note.

## Recording lifecycle cleanup

Count-in cancel, transport stop, and record stop now clear the live-note guard and call `allNotesOff()` where appropriate so hosted AUs do not retain doubled or stale voices.
