# Buildfix 57 — Natural-language Serum / Serum 2 patch parsing

Claude often answers sound-design prompts with prose recipes instead of JSON.
This build keeps the structured JSON path, but adds a conservative natural-language
parser for Serum/Serum 2-style synthesis recipes.

## What it parses

The translation layer now recognizes common prose instructions for:

- oscillator wave / wavetable intent
- Osc A unison and detune
- Osc B bell layer, +12 semitone layer, level hints
- sub oscillator level and octave hints
- Env 1 attack / hold / decay / sustain / release
- Env 2 filter-pluck intent
- filter cutoff, lowpass type, resonance, envelope amount
- chorus / reverb / delay / distortion / high-shelf / LFO movement
- synthwave / pluck style defaults

It accepts natural-language values such as `0 ms`, `150-350 ms`, `25-30% wet`,
`feedback ~30%`, and `3-4 voices`.

## How it works

`SoundAgent` still asks Claude/Ollama for JSON. If the model returns prose, the
agent now falls back to:

```swift
DeviceTranslationLayer.normalizedPluginParams(fromNaturalLanguage:targetName:)
```

Those semantic names are then handed to the same AU target layer used by JSON
responses, so hosted Serum/Serum 2/Vital-compatible parameters can still be
matched by exact, compact, fuzzy, or alias-based lookup.

## Safety

The parser does not execute arbitrary model text. It only extracts known synth
terms and numeric values into a bounded parameter dictionary.
