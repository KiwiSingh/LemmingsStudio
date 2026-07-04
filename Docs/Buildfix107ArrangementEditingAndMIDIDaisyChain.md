# Buildfix107 — Arrangement Clip Editing + MIDI Daisy Chain

Focused pass for core Arrangement editing workflow.

## Added

- Backspace/Delete now deletes the selected Arrangement clip before falling back to track deletion.
- Clip context menus now include Copy and Paste.
- Clip context menus now include Move to Track for both MIDI and audio clips.
- Moving a MIDI clip onto an audio track converts the destination track back to an instrument/MIDI track.
- Moving an audio clip onto a MIDI/instrument track converts the destination track to an audio track.
- Added a global Cmd+E shortcut for Split Clip at Playhead.
- Added app-level copy/paste commands for selected clips.
- Added app-level split logic so the shortcut works outside the Arrangement context menu.

## MIDI input

- LemmingsStudio already connects every visible CoreMIDI source. Buildfix107 changes the live-note guard from a one-bit “note is down” set to a ref-counted active-note table.
- This allows multiple connected keyboards/controllers to layer the same pitch/channel without one suppressing the other.
- MIDI recording remains de-duped for the first active note so stacked live controllers do not automatically print duplicate notes into the clip.

## Not touched

- Splice MCP / download / preview integration.
- Sound Agent / Serum patching.
- AU hosting.
- Metronome and count-in.
