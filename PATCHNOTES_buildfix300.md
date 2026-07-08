# buildfix300 — visionOS MIDI keyboard surfacing + Piano Roll scale fit

## MIDI keyboard surfacing
- Adds an always-visible-by-default collapsible inline MIDI keyboard dock to Piano Roll.
- Adds Show/Hide Keyboard control in Piano Roll.
- Adds Pop Out Keyboard control that opens the existing floating MIDI keyboard scene.
- Adds a direct Keyboard button to the main visionOS top bar so Arrangement and other primary workspaces can launch the floating keyboard without digging through Workspaces.
- Inline keyboard uses the same `virtualMIDINoteDown` / `virtualMIDINoteUp` path as the existing floating keyboard and external MIDI path.

## Piano Roll Fit to Scale
- Adds a Fit to Scale toggle to Piano Roll.
- When enabled, newly drawn notes are mapped to the nearest valid note in the project key and scale.
- When enabled, vertically dragged notes are constrained to the project key and scale.
- Adds Fit Existing Notes action. It fits selected notes, or all notes when no notes are selected.
- Adds project-scale helpers supporting Major, Natural Minor/Aeolian, Harmonic Minor, Melodic Minor, Dorian, Phrygian, Lydian, Mixolydian, Major Pentatonic, Minor Pentatonic, and Blues.
- Piano Roll scale shading now delegates to the same project-scale helper used for fitting.

## Validation
- All 59 visionOS Swift source files parse successfully.
- visionOS shell scripts pass `bash -n`.
- 8 asset catalog JSON files validate.
- MIDI keyboard and Fit to Scale structural assertions pass.
- Release audit passes 20/20 gates.
