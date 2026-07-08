# LemmingsStudio buildfix308 — Spatial keyboard polyphony, glissando, stock instruments, sample browser

## Spatial keyboard
- Enlarged the volumetric keyboard scene to 1.38 m × 0.44 m × 0.26 m.
- Increased physical key geometry to 84 pt white-key width and 268 pt key height.
- Replaced per-key drag capture with a keybed-wide `SpatialEventGesture`.
- Tracks simultaneous event IDs independently for chord polyphony.
- Moving an active event across key boundaries releases the previous note and starts the new note for piano-style glissando/stroking.
- Duplicate touches on one pitch are reference-safe: the pitch releases only after the final touch leaves it.

## Stock instruments
- Added keyboard instrument picker.
- Stock instruments now include Oscillatron, LemmingBass, Glass Lemming, Cloud Pad, and Pluck Nest.
- Extended built-in voice rendering with distinct timbre recipes while preserving note-per-pitch polyphony.

## Sample browser
- Added a Sample Browser workspace.
- Multi-select audio import from the system Files picker.
- Imported files are copied into the app's Application Support sample cache for stable playback.
- Search, preview, Arrangement insertion, and Step Sequencer mapping are supported.
- Browser item model is provider-neutral so future remote adapters can populate the same list.
- UI documents the planned rclone/WebDAV or rclone RC gateway boundary; bf308 does not embed or execute rclone in-process.

## Carried forward
- Minimal MLX model bundle remains the default.
- bf305 Xcode 27 and Swift 6 hotfixes retained.
- bf306/bf307 live MIDI engine startup and audible local spatial-keyboard audition retained.
