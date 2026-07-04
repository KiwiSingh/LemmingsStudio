# Buildfix 204 — Oscillatron / LemmingBass Rack UI + Live MIDI Responsiveness

This buildfix repairs the remaining instrument-device integration bug from buildfix203.

## What was wrong

Buildfix203 restored the audio generator classes for Oscillatron and LemmingBass, but the device rack still treated built-in instruments as hidden track sources. Loading Oscillatron changed the track kind, but removed the visible DeviceModel row, so the rack could still show “No devices on this track yet.”

That made Oscillatron and LemmingBass look stubbed even though the source instrument existed.

## Fixes

- Built-in instruments now get a visible rack DeviceModel row.
- Oscillatron and LemmingBass are still routed as the track source instrument, not as insert FX.
- The audio engine filters built-in instrument DeviceModel rows out of the post-instrument FX chain.
- The DeviceModel node ID is mapped to the live instrument, so rack sliders, MIDI Learn, and automation hit the real generator.
- Old projects/tracks that already have `kind == .oscillatron` or `kind == .lemmingBass` but no visible device row are repaired when the Device Rack opens.
- The rack labels these rows as `Track Instrument` and hides mono/bypass/trash controls so users do not accidentally delete the UI shell while the source instrument remains.
- Live MIDI note audition now starts the CoreAudio graph before gating the first note, preventing the “first note wakes the engine / feels late” behavior.

## Files changed

- `Sources/LemmingsStudio/Effects/Effects.swift`
- `Sources/LemmingsStudio/Audio/AudioEngine.swift`
- `Sources/LemmingsStudio/App/App.swift`
- `Sources/LemmingsStudio/Views/DeviceRack.swift`
