# Buildfix155 — Arrangement Marquee, Finder Drops, Async User Library Index

Scope guard: this patch only targets Arrangement selection/drop handling and the User Samples browser scan path. It does not touch recording, code signing, Splice, Serum/Serum 2/plugin hosting, RVC/build.sh, Demucs, export, mixer clipping, warp, or metronome/count-in.

## Arrangement marquee selection

- Added app-level multi-selection keys for Arrangement MIDI/audio clips.
- Dragging a marquee rectangle across the Arrangement timeline selects every MIDI/audio clip whose rectangle intersects the drag box.
- The selection rectangle can cross tracks, so same-track and multi-track clip selections are both supported.
- Command/Shift click toggles individual clip membership in the current multi-selection.

## Finder drag/drop

- Arrangement drops now accept Finder file URLs, audio/movie file representations, text file paths, and existing in-app drag payloads.
- Dropping a Finder file on an existing lane imports to that track when compatible.
- Dropping a Finder file on the bottom “new track” zone creates a new track.
- Existing plug-in/sample text payload support remains intact.

## User Library scanning

- User library items are now Codable and include size/modified-date metadata.
- The User Samples browser loads the last cached JSON index immediately when available.
- A background task then checks the folder signature using file path + size + modified date.
- If the signature is unchanged, the app keeps the cached index and avoids reclassifying every sample.
- If files were added, deleted, renamed, or modified, it rebuilds the index in the background and rewrites the cache.
- The browser shows a small progress indicator while the background check/indexing is active.

## Files changed

- `Sources/LemmingsStudio/App/App.swift`
- `Sources/LemmingsStudio/Views/Arrangement.swift`
- `Sources/LemmingsStudio/Views/ProDAWShell.swift`
- `Docs/Buildfix155ArrangementFinderAsyncLibrary.md`
