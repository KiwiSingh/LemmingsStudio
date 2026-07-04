# Buildfix103 — Natural-language MIDI fallback for Assistant plans

This buildfix patches the AI Assistant path that previously failed with `Couldn't parse the assistant's plan` when the model returned prose instead of the required JSON operation list.

## What changed

- Added a deterministic natural-language MIDI fallback in `AIAssistant.run(...)`.
- If the model response is not parseable JSON, or if it returns an empty `ops` list, LemmingsStudio now attempts to translate the original user request into concrete DAW operations.
- Added a `set_clip_length` operation so phrase creation can explicitly size the target MIDI clip before adding notes.
- `add_notes` now extends the clip length when generated notes exceed the current clip boundary.
- Added a bass/chord phrase generator for requests like:
  - `Create 4 bars of bass chords on the Bassline track`
  - `Make a 4 bar bassline`
  - `Create 8 bars of chords`

## Bass-chord behavior

For bass-chord requests, the fallback writes real MIDI notes into the target clip:

- one chord per bar,
- key-aware progression from the project key/scale,
- low root + fifth + octave + upper third voicing,
- 4 bars by default when the model/user does not specify length.

This is intentionally a translation-layer safety net. Good models should still return JSON ops directly, but weak/local/prose-heavy models no longer strand the user with no MIDI.
