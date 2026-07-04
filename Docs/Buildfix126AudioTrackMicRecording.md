# Buildfix 126 — Audio Track Mic / Line-In Recording

This buildfix wires the existing audio recorder into the DAW surface so audio tracks behave like real recording tracks instead of hiding the mic recorder in a side panel.

## What changed

- Audio tracks now expose recording controls directly in Arrangement track headers:
  - arm/disarm
  - input monitoring toggle
  - hardware input channel menu (`Input 1`, `Input 2`, etc.)
  - live input level while recording
- Track context menus now include audio-input actions for audio tracks.
- The Recording panel also exposes an input-channel picker for selected audio tracks.
- Recorded clips are named with the captured input channel, for example `Recording · Input 1`.
- Audio input channel selection is saved in `.lemmingsstudio` project documents.
- Mic permission is preflighted before count-in / recording starts. If macOS has not granted access, LemmingsStudio asks for microphone permission and tells the user to press Record again after granting.

## Notes

- Recording uses the current CoreAudio default input device. Choose the physical device in macOS / Audio MIDI Setup, then choose the channel per track in LemmingsStudio.
- Captured Arrangement clips are still mono today. Stereo input pairs and full input-device switching can build on this plumbing.
- Input monitoring can feed back through speakers; use headphones.

## Files touched

- `Sources/LemmingsStudio/Audio/Recording.swift`
- `Sources/LemmingsStudio/App/App.swift`
- `Sources/LemmingsStudio/App/ProjectDocument.swift`
- `Sources/LemmingsStudio/Sequencing/Sequencing.swift`
- `Sources/LemmingsStudio/Views/Arrangement.swift`
- `Sources/LemmingsStudio/Views/AIPanels.swift`
- `Sources/LemmingsStudio/Views/SettingsView.swift`

Splice, Sound Agent, Demucs, AU hosting, Mixer FX, Piano Roll, metronome/count-in timing, and stem code were not touched.
