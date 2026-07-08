# LemmingsStudio buildfix307 — Spatial Keyboard Geometry + Press/Release MIDI

## Fixed

- Rebuilt the floating visionOS MIDI keyboard as a dedicated horizontal physical keybed.
- Removed the layout behavior that compressed the piano into narrow vertical pills.
- Split controls into compact rows above the instrument surface.
- Added fixed physical key geometry, proper black-key overlap, and horizontal scrolling across octave ranges.
- Replaced Button activation plus fixed 180 ms note duration with true press-down note-on and release note-off gestures.
- Preserved latch mode with tap-to-toggle note behavior.
- Added active-key visual feedback and a live route summary.
- Spatial keyboard notes now explicitly audition through the built-in synth while continuing to forward MIDI to active AU and Desktop Bridge destinations.
- Preserved MIDI clip recording hooks and All Notes Off cleanup.

## Carried forward

- buildfix306 audio-engine lazy startup for live MIDI.
- buildfix305 hotfixes for Xcode 27 AVAudio scheduling, Swift 6 isolated deinit, and SwiftUI accent color compatibility.
- visionOS minimal MLX bundle remains the default model profile.
