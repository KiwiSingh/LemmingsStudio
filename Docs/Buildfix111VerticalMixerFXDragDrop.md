# Buildfix111 — Vertical Mixer FX Drag/Drop

User intent: FX in the Mixer should reorder by dragging above/below other FX, similar to Ableton Live's device chain, but vertical inside each mixer strip.

## What changed

- Added mixer-device drag payloads with owner kind, owner ID, and device ID.
- Track, group, and return-bus FX pills now drag as live device instances instead of only dragging a fresh stock-device kind.
- Added narrow vertical drop slots before, between, and after FX in the compact mixer.
- Dropping an FX pill into a slot moves the existing device to that exact insertion point.
- Dropping a stock FX from the browser into a slot inserts a fresh device at that exact position instead of always appending.
- Full Mixer channel/return strips now expose the same vertical drop-slot chain.
- Dragging between track/group/bus chains is supported for stock FX devices.

## Notes

- External AU/VST/VST3 plug-in slots are still added to the target strip when dropped; exact reorderable external plug-in insert-slot UI remains separate because external plug-in slots live outside the stock `devices` array.
- No Splice MCP, Sound Agent, Serum hosting, metronome/count-in, Arrangement clip editing, or stem-splitting files were touched.
