# LemmingsStudio buildfix298

## visionOS Arrangement MIDI loop parity

- Added miniature MIDI-note rendering inside Arrangement MIDI clips.
- Arrangement previews repeat the note miniature across every visible loop cycle.
- Added optional `loopLengthBeats` to `VisionMIDIClip` to preserve source-pattern duration independently of visible clip duration.
- Step Sequencer Print now stamps the source pattern length into the printed MIDI clip.
- Extending a MIDI clip's right edge preserves the original loop source length and extends only the visible clip duration.
- Arrangement playback maps visible clip time back into the source MIDI pattern with modulo timing, so extended MIDI clips loop rather than append silence.
- Expressive MIDI event playback follows the same loop-time mapping.

## Validation

- 59 visionOS Swift files parse successfully.
- visionOS shell scripts pass `bash -n`.
- 8 asset catalog JSON files validate.
- Structural checks confirm loop metadata, loop-aware playback, preview rendering, and Step Sequencer print loop length.
- Release audit passes 20/20 gates.
