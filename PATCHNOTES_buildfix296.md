# buildfix296 — visionOS sequencer print parity + metronome transport sync

- Restores macOS-style Step Sequencer printing: all active lane hits are flattened into one MIDI clip on one Drums track.
- Preserves lane MIDI note numbers, velocity, swing offsets, and clip length.
- Printed Step Sequencer track is moved to the top of Arrangement and selected immediately.
- Live sequencer is disabled after printing to prevent duplicate playback against the printed clip.
- Removes independent audio-render metronome scheduling during transport playback.
- Metronome click events now originate from the same transport callback boundary as sequencer step dispatch, eliminating relative clock drift between the two paths.
- Click synthesis remains in VisionAudioEngine.
