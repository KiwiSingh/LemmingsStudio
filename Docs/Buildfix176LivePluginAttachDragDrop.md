# Buildfix 176 — Live Plug-in Attach + Drag/Drop Editor Reliability

## Problem
Opening Serum 2 or another instrument plug-in could show:

> Could not attach Serum2 to the live engine. Rescan plug-ins or insert it on an instrument track before opening the editor.

That happened because the AU editor path correctly refused to open a detached editor-only instance, but its recovery path only tried the currently selected track. Drag/drop, VST3 browser rows with AU counterparts, and stale selection state could therefore leave the rack slot visible while no live AU instance was attached to the engine.

## Fix
- Instrument editor opening now searches all tracks for the slot before falling back to the selected track.
- If no suitable track exists, LemmingsStudio automatically creates/configures a real instrument track and attaches the AU there.
- VST/VST3 browser entries that have an AU counterpart now open the live AU editor instead of surfacing a dead-end error.
- Drag/drop plug-in insertion now rebuilds, starts/warms the engine, and immediately opens the live editor when possible.
- Added AU name normalization so labels such as `Serum2`, `Serum 2`, `Xfer Serum 2`, or VST/AU-decorated names resolve to the same hosted AU.

## Expected behavior
Dragging Serum 2, clicking Add, or revealing the slot should load a real live instrument instance, open the vendor editor, and keep that editor attached to the same AU object the engine renders/records/automates.
