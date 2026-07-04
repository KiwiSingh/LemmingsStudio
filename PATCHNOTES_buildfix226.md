# LemmingsStudio buildfix226 — Windows feature-parity UI pass

This buildfix starts replacing the Windows placeholder shell with real DAW workspaces that mirror the macOS app structure.

## Windows UI parity work

- Added a native Windows **Step Sequencer** tab.
- Added a native Windows **Piano Roll** tab.
- Added Project menu entry: **Add Sequencer Track**.
- Windows tabs now include Arrangement, Step Sequencer, Piano Roll, Devices, Mixer, Automation, MIDI/Hardware, AI, Splice, and Log.

## Step Sequencer

- Real per-track `UseStepSequencer` state.
- Real serializable `StepPattern`, `StepHit`, and `SequencerLayer` project models.
- 16-step grid by default, adjustable up to 64 steps.
- Adjustable steps-per-beat.
- Kits/grooves: Tech House, Guaracha, EDM, Lo-Fi.
- Clear lane via right-click on any step in that lane.
- **Print to Arrangement** creates a new editable MIDI clip/track from the pattern.
- Playback/export now renders enabled step-sequencer tracks, so the grid is not cosmetic.

## Piano Roll

- Real native MIDI clip editor.
- Select instrument/MIDI track and MIDI clip.
- Create MIDI clips.
- Click grid to add notes.
- Right-click notes to delete.
- Quantize to 1/16.
- Edits are reflected in playback/export through the existing Windows audio renderer.

## Audio/project model

- `ProjectClip` now includes gain/pitch fields for Windows project compatibility with the macOS clip model direction.
- Instrument tracks now default to `Oscillatron` instead of the previous generic “Windows Stock Synth” label.
- Step Sequencer tracks render through the same built-in instrument/device chain used by MIDI clips.

## Notes

This does not claim every last macOS feature has reached perfect Windows parity in one pass. It does remove the most obvious placeholder gap: the Windows UI now has real Step Sequencer and Piano Roll workspaces, and their edits are connected to project state and rendering instead of being static stubs.
