# buildfix301 — visionOS spatial MIDI keyboard, record transport, Piano Roll framing

## Fixed
- Replaced the oversized MIDI keyboard dashboard with a compact keyboard-only world-space window that can be independently placed in visionOS space.
- Removed the docked Piano Roll keyboard from the primary editor layout.
- Added a prominent primary Record control to the main transport.
- Record is context-aware: MIDI clips/tracks record virtual-keyboard note-on/note-off timing into the selected MIDI clip; non-MIDI context falls back to the existing audio record path.
- Added MIDI-record status to the world-space keyboard.
- Added automatic Piano Roll framing around the selected clip's actual pitch range and content duration.
- Added a manual Frame Notes action.
- Added visible C-note pitch labels inside the Piano Roll grid.

## Validation
- 59 visionOS Swift files parse with swiftc frontend.
- visionOS build/release shell scripts pass bash -n.
- asset catalog JSON files validate.
- structural assertions verify spatial keyboard scene, primary Record control, MIDI recording hooks, and Piano Roll framing.
