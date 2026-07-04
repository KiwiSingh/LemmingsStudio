# Buildfix 170 — Automation Point Editing

Scope: QoL pass for automation editing after buildfix167/168/169.

## What changed

- Track automation points are now editable directly on the automation lane.
- Global tempo automation points are now editable directly on the tempo lane.
- Drag an existing point to move it horizontally/vertically.
- Right-click an existing point and choose Delete to remove only that point.
- Selected/active points draw larger with a white fill and accent outline so it is clear which breakpoint is being edited.
- Device On lanes snap dragged values to 0 or 1 so bypass automation remains a clean on/off envelope.
- Tempo automation clamps dragged points to the project length and to the lane’s 40–220 BPM editing range.

## Guardrails

- No stem splitter logic touched.
- No stem backend/package/build.sh changes.
- No recording, code signing, Splice, Serum/Serum 2, AU hosting, export, mixer, warp, metronome, MIDI learn, or User Library scanner changes.
