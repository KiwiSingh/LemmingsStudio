# Buildfix125 — Browser drag/drop, preview, folder browsing

## Why

The User Samples browser still exposed a `Layer` button that routed one-shots into the Step Sequencer. That made sample browsing feel like a sequencer-lane importer instead of a DAW browser. The FX/Plugins browser also had search, but not enough browse affordance.

## Changes

### User Samples

- Replaced the Step Sequencer `Layer` action with Arrangement-oriented `Add Clip` / `Add MIDI` actions.
- Rows remain draggable via the existing sample pasteboard payload; Arrangement/track drops continue to import audio/MIDI clips instead of creating sequencer layers.
- Added audio preview for one-shots/loops using `AVAudioPlayer`.
- Added MIDI preview using the selected instrument/MIDI track and short note auditions.
- Added Stop/Preview state, preview status text, and context-menu actions.
- Added folder buckets so the scanned User Library can be browsed by root/folder instead of only searched.
- Added Expand All / Collapse controls and visible root-folder path.

### FX / Plugins

- Built-in devices are now browsable through disclosure sections by category.
- Scanned plugins are grouped into browsable sections by format, role, and manufacturer.
- Rows emphasize drag/drop targets while still keeping an explicit Add button.
- Added context-menu helpers and Finder reveal for scanned plugins when a path is available.

### Library quick presets

- Removed the visible User Samples quick action that implied Step Sequencer sample-layer importing.
- User Samples now points at choosing/scanning the User Library or importing an audio clip.

## Untouched

Splice MCP/download/preview, Sound Agent, Demucs, AU hosting, Arrangement internals, mixer drop slots, metronome/count-in, and stem splitting were not touched.
