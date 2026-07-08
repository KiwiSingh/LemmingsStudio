# LemmingsStudio buildfix243 — Windows MIDI / Piano Roll finishing pass

## Piano Roll
- Multi-note selection with Ctrl-click and marquee selection.
- Note drag movement, right-edge resize handles, delete, duplicate, time nudge and pitch nudge.
- Keyboard transpose by semitone and octave.
- Selective or whole-clip quantize using 1/4, 1/8, 1/16 and 1/32 grids.
- Humanize timing and velocity.
- Editable velocity lane.
- Editable CC1 Mod Wheel lane.
- Editable Pitch Bend lane.
- Editable Sustain Pedal lane.
- Scale highlighting for Chromatic, Major, Minor, Dorian and Pentatonic modes using the project key root.
- Ghost notes from overlapping MIDI clips on other MIDI/instrument tracks.
- Live note preview through the selected track's stock instrument character.

## MIDI recording
- Loop Record option creates successive MIDI take clips for each recording cycle.
- Existing Overdub/Replace, count-in, quantize-on-record, sustain, CC, pitch bend, program change and pressure capture remain available.

## Notes
- Expressive lanes edit the same persistent MidiEvents already consumed by the Windows stock synth render engine and forwarded through the native VST3 render path where supported.
- This source pass was structurally checked in the Linux container but requires compilation/runtime validation on Windows.
