# Buildfix93: Serum/Serum 2 Pluck Envelope Repair

Buildfix92 proved that the Sound Agent can now reach real Serum/Serum 2 AU parameters, but the default pluck recipe was too aggressive: it set amp-envelope decay/sustain/release too low, opened noise too eagerly, and used a heavy filter-envelope transient. On Serum 2 this can collapse an intended synth pluck into a white-noise click/blip.

Buildfix93 keeps the broad Serum static map, but adds a musicality pass for Serum-style pluck/synthwave requests:

- Amp envelope is now short but audible, not click-length.
- Env 1 decay/sustain/release floors are enforced after model JSON/prose parsing.
- Env 2/filter modulation is reduced so the filter does not slam shut instantly.
- Noise is disabled unless the prompt explicitly asks for noise/air/breath.
- Filter cutoff has a higher floor for plucks so oscillator body remains audible.
- Delay/reverb wet amounts are capped for plucks so the transient does not smear or mask the body.

Splice MCP/download/preview code was not touched.
