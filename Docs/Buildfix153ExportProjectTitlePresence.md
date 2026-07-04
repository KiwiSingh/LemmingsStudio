# Buildfix153 — Export entry points and project title/presence sync

## Changes

- Added top-level export actions to the macOS menu bar.
- Added a compact Export menu to the transport strip so export is no longer hidden in the Studio inspector.
- Export file names now default to the current project display name.
- Saving a project now syncs the in-memory project name from the saved `.lemmingsproject` filename.
- Opening a project uses the file name when the saved document still says `Untitled`.
- Discord Rich Presence is refreshed after save/load/new so it no longer stays stuck on `Untitled` after saving.
- Added a tiny AppKit title bridge so the macOS window title shows `<Project Name> — LemmingsStudio` instead of only `Lemmings Studio`.

## Intentionally not touched

- Recording and code-signing fixes from Claude.
- Splice MCP/download/preview.
- Serum/Serum 2/plugin hosting fixes.
- AU hosting, RVC/build.sh, Demucs/stems, Piano Roll, browser drag/drop, monitor modes, Mixer FX, warp controls, metronome/count-in.
