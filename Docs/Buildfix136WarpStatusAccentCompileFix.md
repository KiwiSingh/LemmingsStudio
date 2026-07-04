# Buildfix136 – Warp Status Accent Compile Fix

Fixes the buildfix135 compile regression where the warp status label referenced `LSTheme.accent`, which does not exist in the current theme palette.

## Changed

- `Sources/LemmingsStudio/Views/ProDAWShell.swift`

## Fix

- Replaced the invalid `LSTheme.accent` reference with `LSTheme.focus` for the manual clip tempo override status color.

## Not touched

Splice, Sound Agent, Demucs/stems, AU hosting, Piano Roll, browser drag/drop, mic recording/input devices, monitor modes, Mixer FX, and metronome/count-in timing were not touched.
