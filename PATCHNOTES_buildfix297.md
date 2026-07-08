# buildfix297 — visionOS sequencer workspace isolation + verified MIDI print

## Fixed
- Live Pattern playback is now gated to the Step Sequencer primary workspace.
- Leaving Step Sequencer clears the active sequencer step so no stale step state leaks across views.
- Print to Arrangement materializes one MIDI clip containing all active lane notes.
- Printed notes receive explicit UUIDs.
- The target track is rebuilt and reinserted as a complete value, avoiding fragile nested mutation.
- Print verifies the committed clip by ID and note count before switching to Arrangement.
- Print reports a hard failure if the MIDI payload was not committed.

## Behavior
- Live Pattern only auditions in Step Sequencer.
- Arrangement playback only plays Arrangement clips.
- Print creates one `Step Sequencer Pattern` MIDI clip on one `Step Sequencer` Drums track.
- All active lane note numbers and timing are preserved in that clip.
