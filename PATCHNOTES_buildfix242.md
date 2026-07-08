# LemmingsStudio buildfix242 — Windows Arrangement View polish

This pass turns the Windows Arrangement View from a mostly visual clip surface into a real editing surface.

## Editing
- Move one or multiple selected clips by dragging.
- Trim selected clips from left/right edge handles.
- Split selected clips at pointer position (`S` or context menu).
- Duplicate (`Ctrl+D`).
- Copy/cut/paste (`Ctrl+C`, `Ctrl+X`, `Ctrl+V`) with multi-track relative placement retained.
- Delete selected clips (`Delete` / `Backspace`).
- Arrow-key nudging follows the active snap grid.
- Marquee and Ctrl/Shift multi-selection retained.

## Snap/grid
- Toggle snap.
- 1 Bar, 1/4, 1/8, 1/16, 1/32 grids.
- Grid is used consistently by move, trim, paste, duplicate, nudge and file/Splice drops.

## Navigation
- Ctrl+wheel: horizontal zoom, anchored under pointer.
- Shift+wheel: horizontal scroll.
- Alt+wheel: vertical track zoom.
- Wheel: vertical scroll.

## Visual polish
- Selection trim handles.
- Real waveform peak extraction/caching for supported audio files through NAudio instead of fake randomized waveforms.
- MIDI clips render their actual notes only.
- Visible snap state in timeline header.
- Frozen track status in headers.

## Safety/compatibility
- Clip operations mutate the existing project model and therefore persist through the existing ProjectIO save/load path.
- MIDI split separates note and event content across the split point.
- Splice and file drops now honor the active Arrangement snap grid and scrolled/zoomed coordinate transform.

## Audio trim correctness
- Added `ProjectClip.SourceOffsetBeats` to persist non-destructive left trims and audio split offsets.
- AudioEngine now crops decoded/warped clip audio to the clip source offset and visible clip length, so Arrangement trimming/splitting changes playback, bounce, freeze and export rather than only the UI rectangle.
