# Buildfix152 — New-track drop zone and loop classification

- Fixed Arrangement's bottom **Drop here for new track** zone so file drops explicitly import with `forceNewTrack: true` instead of relying on the current selection being nil.
- File URL drops now pass the destination track through to the media importer; dropping on the bottom zone creates a new audio/MIDI track, while dropping on an existing lane imports onto that lane when compatible.
- Browser/sample pasteboard drops with no target track now force new-track imports too, so User Library drag/drop behaves like the visible drop-zone promise.
- Audio import now accepts an explicit target track and a force-new-track mode.
- MIDI import now accepts force-new-track mode as well.
- User Library scan classification was hardened:
  - filename/folder tokens like `loop`, `loops`, `bpm`, `_lp`, `groove`, `riff`, `phrase`, `melody`, `chord`, and `bhangra` classify as Loops;
  - detected tempo classifies as Loop;
  - audio duration >= 1.5s classifies as Loop unless it clearly names a one-shot;
  - short named hits/kicks/snares/etc. remain One-shots.

Not touched: recording, code signing, Splice MCP/download/preview, Serum/Serum 2/plugin fixes, AU hosting, RVC/build.sh, Demucs, Piano Roll editing, monitor modes, Mixer FX, warp controls, and metronome/count-in.
