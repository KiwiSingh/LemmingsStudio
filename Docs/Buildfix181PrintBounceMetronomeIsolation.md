# Buildfix 181 — Step Sequencer re-print isolation + bounce/freeze metronome exclusion

## Fixed

### Step Sequencer print overlap
Printing the same Step Sequencer pattern multiple times now silences/deactivates older generated print tracks from the same source before creating the new print. This prevents an earlier print, such as a kick/hat/snare version, from doubling underneath a later hats/snares-only print.

Implementation notes:
- Added print-origin tracking on generated Arrangement print tracks.
- The source track remembers its latest generated print target.
- Re-printing mutes and deactivates previous generated print clips from the same source/origin.
- The live Step Sequencer render cursor and all currently held notes are reset after printing.

### Bounce/freeze rendering the metronome
Freeze/Bounce Track in Place now forces an Arrangement-scope offline render with the metronome disabled. This prevents the click source from being captured as a fake bounce/freeze clip.

Implementation notes:
- `OfflineRenderer.renderStereo` now accepts `includeMetronome` and `forcedPlaybackScope` options.
- Bounce/freeze calls render with `includeMetronome: false` and `forcedPlaybackScope: .arrangement`.
- Offline renders now start from beat 0 instead of inheriting the live playhead position.
- Bounce length is temporarily scoped to the selected track’s actual active MIDI/audio content instead of blindly rendering the entire project length.

## Files changed
- `Sources/LemmingsStudio/App/App.swift`
- `Sources/LemmingsStudio/Audio/Export.swift`
- `Sources/LemmingsStudio/App/ProjectDocument.swift`
- `Sources/LemmingsStudio/Sequencing/Sequencing.swift`
