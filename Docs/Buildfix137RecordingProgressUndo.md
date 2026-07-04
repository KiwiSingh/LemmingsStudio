# Buildfix 137 — Audio Recording Progress + Clip Undo

Fixes the blank-recording/provisional-clip confusion and expands undo coverage for core clip operations.

## Recording

- Restarts/resets the AVAudioEngine input graph after changing the selected CoreAudio input device, before installing the input tap.
- Keeps the existing per-track device and channel selection.
- Starts exactly one provisional audio clip for a recording take.
- Adds a wall-clock progress timer so the provisional clip visibly grows while recording, even before audio buffers arrive.
- Updates clip length from captured samples when audio buffers arrive.
- Emits a recorder warning if no input buffers arrive after a short delay.
- Keeps an empty take visible on stop, sized to the recorded duration, rather than collapsing into an invisible 0-length sliver.
- Selects the actual owner track of the recorded audio clip on stop.

## Undo / Redo

- Recording an audio take is now undoable/redoable.
- Importing an audio clip is now undoable/redoable.
- Deleting audio clips is now undoable/redoable.
- Deleting MIDI clips is now undoable/redoable.
- Duplicating MIDI clips from Arrangement is now undoable/redoable.
- Duplicating audio clips from Arrangement is now undoable/redoable.

## Untouched

Splice MCP/download/preview, Sound Agent, Demucs/stems, AU hosting, Piano Roll, browser drag/drop, monitor modes, Mixer FX, warp controls, and metronome/count-in timing were not touched.
