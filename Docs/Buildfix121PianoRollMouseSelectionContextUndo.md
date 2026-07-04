# Buildfix121 — Piano Roll mouse selection + contextual undo restore

## Scope

This patch restores Piano Roll editing behavior without touching Splice, Demucs,
Sound Agent, AU hosting, mixer, metronome, count-in, or Arrangement logic.

## Fixes

- Notes in Piano Roll are now selected with the mouse instead of being deleted on click.
- Shift/Cmd-click toggles note selection.
- Dragging over the Piano Roll creates a marquee selection rectangle.
- Header actions now include Select All, Delete Selected, and Fit Selected to Scale.
- Delete/Backspace routes to selected Piano Roll notes first when the Piano Roll is focused.
- Piano Roll note add/delete/fit edits are committed through a contextual undo helper.
- Cmd+Z/Cmd+Shift+Z prefer the currently focused Piano Roll context before falling back to global project/plugin edits, preventing note edits from accidentally undoing unrelated Serum/plug-in state.

## Changed files

- `Sources/LemmingsStudio/Views/PianoRoll.swift`
- `Sources/LemmingsStudio/App/App.swift`
