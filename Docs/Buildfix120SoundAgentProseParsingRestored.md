# Buildfix120 — Sound Agent prose parsing restored

Buildfix119 fixed misleading status text, but it made the no-JSON path feel like it
was only recognizing the user's prompt family rather than actually reading the
assistant's natural-language patch recipe.

This pass restores that intended behavior:

- Labelled prose lines like `Oscillator A: sine/triangle body`, `Filter: warm low-pass, low resonance`, and `Amp envelope: fast attack, medium decay, low sustain, playable release` now translate into concrete plug-in parameter moves even when the model does not provide numbers.
- Markdown/bullet recipes from Claude/Ollama/Perplexity-style models now contribute actual Serum-style parameters before the static family fallback runs.
- Rhodes/electric-piano prose is parsed as a real recipe: sine/triangle body, quiet octave-up tine layer, percussive envelope, warm filter, chorus, tremolo, and subtle room.
- The status text now correctly distinguishes prompt-derived params, response-prose params, and true macro fallback.

No Splice, Demucs, Arrangement, metronome/count-in, AU-hosting lifecycle, or mixer code was touched.
