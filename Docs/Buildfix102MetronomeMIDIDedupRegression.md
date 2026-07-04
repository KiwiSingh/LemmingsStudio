# Buildfix102 – Metronome + MIDI Count-In Regression Fix

Scope: fixes the regression where the count-in could make the metronome inaudible and the first notes played from a MIDI keyboard could sound stacked/retriggered even though the clip did not record duplicates.

Changed files:

- `Sources/LemmingsStudio/Audio/AudioEngine.swift`
- `Sources/LemmingsStudio/Audio/MIDIInput.swift`
- `Sources/LemmingsStudio/App/App.swift`

## Fixes

- Keeps the metronome source node alive whenever the metronome is enabled, instead of allowing AVAudioEngine to mark it silent between count-in/playback buffers.
- Adds a short transient component to the metronome click so it is audible like a DAW click instead of a fragile sine tick.
- Prevents CoreMIDI source reconnection duplication by tracking connected source unique IDs. Repeated CoreMIDI notifications no longer connect the same keyboard source multiple times to the same input port.
- Preserves the live MIDI note-down guard across the count-in → record transition. Clearing it at the boundary could retrigger held notes and make Serum/other hosted instruments sound like multiple notes fired.

Splice, Sound Agent patch generation, AU mapping, Arrangement resize, and fresh-init sound design were not touched.
