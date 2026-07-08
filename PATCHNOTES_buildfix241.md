# buildfix241 — Windows Bounce / Freeze / Flatten / Consolidate parity

## Added

- Project menu commands for Bounce Selected Clip, Consolidate Selected Clips, Freeze Selected Track, Unfreeze Selected Track, and Flatten Selected Track.
- Rendered assets go to `Media/Renders` beside saved projects, with a Documents fallback for unsaved projects.
- Bounce renders through the source track device chain and automation and creates a new editable audio clip while leaving the source intact.
- Consolidate renders same-track selected clips into one audio file/clip and removes the source selection.
- Freeze is non-destructive and reopen-safe: the full editable Track state is serialized into project JSON before substitution with rendered audio.
- Unfreeze restores the original clips, devices, automation, MIDI, sequencer state, and device state from the embedded backup.
- Flatten permanently keeps rendered audio and discards the freeze backup after an explicit warning.
- Render-edit operations exclude the metronome and preserve effect tails from the engine render window.

## Notes

The Windows project could not be compiled in the Linux patching container. Validate with the normal Windows build command and exercise save/reopen across Freeze and Unfreeze before release.
