# Buildfix252 — visionOS Piano Roll + Step Sequencer

## Piano Roll

- Added dedicated visionOS Piano Roll window.
- Edits the selected Arrangement MIDI clip directly.
- Note add/select/move workflow with native note preview.
- Quantize, humanize, semitone transpose, and octave transpose commands.
- Scale-aware row highlighting using project key/scale metadata.
- Ghost-note display from other MIDI clips.
- Velocity lane editing.
- Persistent expressive MIDI event lanes for:
  - CC1 mod wheel
  - 14-bit pitch bend
  - sustain pedal CC64
- Expressive events are stored in `VisionMIDIClip.midiEvents` and forwarded during transport to native AUv3 and Desktop Bridge MIDI paths.

## Step Sequencer

- Added persistent `VisionStepSequencerState` project model.
- Variable 8/16/24/32/48/64-step patterns.
- Steps-per-beat timing model.
- Swing control.
- Per-lane MIDI note, volume, pan, sample path, and hit arrays.
- Live step indication follows project transport.
- Sample assignment through the system file importer.
- Sample-backed lanes trigger native one-shot playback.
- MIDI-backed lanes trigger stock synth, hosted AUv3, or Desktop Bridge destinations.
- Per-lane clear operation.
- Print to Arrangement creates a normal editable MIDI clip, including swing timing.

## Integration

- Added Piano Roll and Sequencer launch buttons to the main visionOS toolbar.
- Added dedicated `WindowGroup` scenes for both editors.
- Updated root and visionOS README status sections.
- Kept project decoding backward-compatible by making new event/sequencer fields optional or defaultable.

## Validation performed in this environment

- Swift source delimiter/structure checks across the visionOS target.
- `build-visionos.sh` shell syntax validation.
- visionOS `Info.plist` validation.
- ZIP integrity verification.

Actual Xcode/visionOS SDK compilation still requires a Mac with Xcode and the visionOS SDK installed.
