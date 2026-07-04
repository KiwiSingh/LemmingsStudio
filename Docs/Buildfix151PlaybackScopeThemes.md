# Buildfix151 — Playback Scope + No Step Print Doubling + Three Themes

## Summary

This build fixes the Step Sequencer / Arrangement double-trigger problem and adds three Liquid Glass theme presets.

## Playback scope

Playback now follows the visible workspace:

- **Step Sequencer**: only live Step Sequencer grids/lanes render. Arrangement MIDI/audio clips are muted while this view is active.
- **Arrangement**: Arrangement MIDI/audio clips render. Live Step Sequencer grids do not also fire underneath printed clips.
- **Piano Roll**: Arrangement MIDI clips render so edited notes can be heard, but live Step Sequencer grids remain muted to avoid overlap.

Switching workspace updates the audio engine playback scope and sends all-notes-off, preventing stale held notes from leaking across views.

## Print to Arrangement

`Print to Arrangement` now mutes the source track's live Step Sequencer after creating the printed Arrangement track. The printed MIDI track remains editable and plays normally in Arrangement view, without the original grid doubling the same notes.

## New themes

Added three additional Liquid Glass visual themes:

- **Lemmings** — cute rodent / burrow / paw-print motif.
- **Hamster After Dark** — original black-and-orange hamster-nightclub palette, loosely inspired by adult-video-site contrast without copying logos.
- **Kitty and Buds** — pastel kitty-island / flowers / leaves motif, original glyphs and palette.

## Untouched

Did not touch:

- Claude's recording fixes
- code-signing / mic permission logic
- Splice MCP/download/preview
- Serum / Serum 2 / hosted plug-in fixes
- AU hosting
- RVC / build.sh packaging
- Demucs/stems
- Piano Roll editing
- browser drag/drop
- monitor modes
- Mixer FX
- warp controls
- metronome/count-in timing
