# Buildfix158 — Stem Split Popup + Start Button

## Scope
Fixes the accidental nested context-menu UX introduced for selected-clip stem splitting.

## Changes
- Replaced the right-click `Stem Split Selected Clip` submenu stack with a single `Stem Split Selected Clip…` command.
- The command now opens a real macOS popover instead of a submenu chain.
- The popover includes:
  - backend picker (`Auto`, `MLX Demucs`, `Official Demucs`, `Core ML`)
  - model picker (`htdemucs`, `htdemucs_ft`, `htdemucs_6s`)
  - stem isolate toggles
  - output routing toggles for merge-to-single-audio-track and submix group
  - an explicit `Start Stem Split` button
  - real-time progress/status while extraction runs
- The selected audio clip remains the stem-split input.
- Finished stems still auto-import into new Arrangement audio tracks.

## Files touched
- `Sources/LemmingsStudio/Views/Arrangement.swift`
- `Docs/Buildfix158StemSplitPopupStartButton.md`

## Guardrails
Did not touch recording, code signing, Splice, Serum/Serum 2/plugin fixes, AU hosting, RVC/build.sh, Demucs packaging, export, mixer clipping, warp controls, metronome/count-in, or Finder drop import.
