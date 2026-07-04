# buildfix91 — Serum 2 prompt preservation + wider AU mapping

Scope: Sound Agent / hosted AU mapping only. Splice MCP/download/preview files are untouched.

## Fixes

- Stops deriving the visible preset name by blindly taking the first four words of the prompt. A prompt like `Create me an '80s style synthwave pluck` now becomes a useful display name such as `80s Synthwave Pluck`, not `Create Me An 80S`.
- Parses the original user prompt as a first-class sound-design source, not only the model response. This prevents a weak local model/Claude response from reducing the sound to a tiny or nonsensical parameter set.
- Adds a direct Serum-style recipe for `80s` / `synthwave` / `pluck` prompts: oscillator level/wavetable/unison/detune, filter cutoff/resonance/drive, Env 1 pluck shape, Env 2 filter movement, chorus, delay, reverb, master volume, and polyphony.
- Broadens AU fuzzy matching for common Serum/Serum 2 labels such as `A Vol`, `A WTPos`, `Fil Cutoff`, `Fil Drive`, `Env1 Atk/Dec/Sus/Rel`, `Sub Vol`, `Noise Vol`, FX wet/mix labels, and master volume variants.

## Serum 2 caveat

Serum 2 can expose a dynamic/host-dependent parameter set. LemmingsStudio can only schedule AU automation for parameters the AU publishes to the host. The agent now targets far more likely Serum labels, but if Serum only publishes a small set, the result summary will still show skipped/unmatched controls rather than pretending the full patch was written.
