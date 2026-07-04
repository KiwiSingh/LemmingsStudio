# LMMS stock-device polish notes — buildfix 67

This pass uses LMMS as architecture inspiration only. We do not copy LMMS plugin code or presets.

Useful LMMS takeaways:

- Small bundled devices should be immediately audible and musical, not empty placeholders.
- Stock devices should ship with sensible default ranges and friendly names.
- Built-in instruments/effects should be safe, deterministic, and lightweight enough for beta users to stack heavily.
- Third-party/bundled content should be license-clean. For sample/preset style assets, prefer permissive/CC0 sources.

LemmingsStudio changes in this pass:

- `Drum Drive Bus` is now a dedicated drum bus processor with drive, boom, transient snap, crunch, and output.
- `Noise Erode` is now a proper erosion/noise coloration device with frequency, width, mode, amount, and dry/wet.
- `Record Distortion` is now a vinyl-style lo-fi color device with drive, dust, warp, age, and dry/wet.
- `Channel Shaper` is now a simpler channel-strip style processor instead of falling back to the eight-band EQ.

These are original Swift DSP implementations written for LemmingsStudio. They are inspired by the kind of bundled instrument/effect ecosystem LMMS has, but they are not ports or copies.
