# Buildfix96 – hosted AU recording + click-in

This buildfix keeps Serum 2 and other hosted AU instruments on a single live instance across the Sound Agent, editor window, playback, count-in, and recording paths.

## Fixes

- Hosted AU instruments are cached per track/plugin/sample-rate so a graph rebuild no longer discards the agent-created patch and recreates Serum 2 at Init.
- Hosted AU creation now prefers `AVAudioUnit.instantiate(..., .loadOutOfProcess)` and retains the `AVAudioUnit` wrapper, so the visible vendor editor and the engine-rendered AU share the same remote-hosted instance.
- Source nodes now explicitly avoid reporting live AU tracks as silent, preventing Serum 2 from entering/remaining in a visible “DAW suspended processing” state while Lemmings is counting in or recording.
- Record start/count-in explicitly starts the engine, starts transport if needed, and warms hosted AU render blocks before arming MIDI/audio overdub.
- Metronome is on by default for new/default installs.
- Added a transport-bar click-in/count-in toggle next to the metronome button.

## Not touched

Splice MCP/download/preview integration was not modified.
