# Buildfix154 — Export progress, clipping detection, and project metadata persistence

Scope guard: this patch avoids recording, code signing, Splice, hosted plug-ins, RVC/build.sh, Demucs, Piano Roll editing, browser drag/drop, monitor modes, Mixer FX, warp controls, and metronome/count-in.

## Export progress

- `OfflineRenderer` now reports render/write progress through a progress callback.
- `AppState.export(format:)` updates `exportProgress`, `exportIsActive`, and `exportStatus` in real time.
- The Studio export panel shows a linear progress bar and percentage while an export is running.
- The pro transport strip also shows compact export progress so the user does not need to keep the Studio panel open.

## Clipping detection

- Offline export now scans rendered stereo samples for true full-scale clipping before writing/transcoding.
- Export completion status includes peak dBFS and a clipping/no-clipping verdict.
- Mixer channel meters now expose a red `CLIP` badge when their smoothed peak hits the near-full-scale threshold.
- Master meter also reports clipping instead of only showing a capped green/yellow/red bar.
- Compact mixer meters turn red and show an exclamation indicator when a track clips.

## Project BPM/key save fix

- `saveProject`, `saveProjectAs`, and `saveProject(to:)` now call `commitPendingProjectMetadataEdits()` first.
- `TempoTextField` writes its current draft text into `AppState`, so Cmd-S while the BPM field is still focused no longer saves the old tempo.
- Project documents now redundantly store `bpm` and `keyName` alongside the existing `tempo`, `keyRoot`, and `scaleName` fields for easier inspection/debugging.
- Loading still uses the canonical project tempo/root/scale fields, preserving compatibility with older `.lemmingsproject` files.
