# Buildfix 182 — Non-destructive Step Prints + Visible Arrangement Snap

## Fixed

- Re-printing a Step Sequencer pattern no longer mutes or deactivates older printed Arrangement tracks.
- Older prints are treated as normal Arrangement material once created. They stay editable, draggable, and audible unless the user explicitly mutes or disables them.
- The duplicate-print guard now removes only the live/generated Step Sequencer preview clips from the source track before creating the new print. This prevents hidden sequencer preview overlap without poisoning previous Arrangement prints.
- Projects touched by buildfix181 are repaired on the next print by reactivating previously deactivated print clips from the same sequencer source; tracks are auto-unmuted only when they show that deactivated-clip poison state.
- Moving a MIDI or audio clip to another track now forces the moved clip active, so a previously deactivated print can be recovered simply by moving it.

## Snap-to-grid

- Arrangement now exposes Snap and Grid controls directly in the Arrangement toolbar.
- Clip dragging and resizing already used the snap engine; the controls are now visible where the editing happens.
- New MIDI clip creation by click-drag now snaps both start and end boundaries to the selected grid.
- New MIDI clips, MIDI imports, audio imports, and Step Sequencer prints now use the same Arrangement snap unit instead of a hard-coded 16th-note fallback.
