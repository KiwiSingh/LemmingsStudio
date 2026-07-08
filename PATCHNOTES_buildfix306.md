# LemmingsStudio buildfix306 — Spatial MIDI Keyboard Visibility + Live Note Routing

## Fixed

- Reworked the visionOS floating MIDI keyboard shell and keys from translucent material-heavy surfaces to high-contrast opaque physical surfaces.
- White keys now render fully opaque; black keys use solid near-black fills with stronger edge separation.
- Increased inactive and active key outlines for legibility inside a volumetric window.
- Preserved active-note accent feedback while making the keyboard readable against passthrough and bright environments.
- Fixed silent spatial keyboard input: live MIDI note-on now lazily starts `VisionAudioEngine` when transport playback has not already started it.
- AU instrument hosting and desktop bridge MIDI routing remain intact; the built-in synth fallback now becomes audible immediately on first key press.
- Prior bf305 Xcode 27 hotfixes remain included.
- Minimal MLX bundle profile remains the default.
