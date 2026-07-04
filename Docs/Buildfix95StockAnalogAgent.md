# Buildfix95 — Stock Analog Sound Agent Coverage

This build closes the gap where buildfix94 expanded AU synth mappings but left the stock analog instruments treated as second-class targets.

## What changed

- Added a shared `StockAnalogPatchable` surface for stock synths that are ultimately powered by `AnalogSynth` voices.
- The Sound Agent can now patch:
  - `AnalogSynth` / Built-in Analog
  - `Oscillatron`
  - `LemmingBass` / Bass Synth
  - `DubstepWranglerInstrument` when used as a synth instrument
  - the melodic Tumbi/Reed voices inside `BhangraArchitectInstrument`
- `BuiltinAnalogTarget` now accepts any `StockAnalogPatchable`, not only a raw `AnalogSynth`.
- `AudioEngine` exposes `liveStockAnalog(for:)` so the app can find the live rendered stock synth instance, not a detached preset object.
- The built-in analog target now maps common AI/plug-in names such as `Filter Cutoff`, `Env 1 Decay`, `Osc B Level`, `Detune`, `Width`, `Volume`, etc. onto the actual stock controls:
  - `cutoff`
  - `resonance`
  - `attack`
  - `decay`
  - `sustain`
  - `release`
  - `detuneCents`
  - `osc2Mix`
  - `gain`
- The offline stock synth recipe now has explicit musical ADSR recipes for plucks, keys, leads, supersaws, saws, basses, 808s, pads, synthwave, and modifier words like wide/thin/punchy.
- The LLM system prompt now describes stock analog controls directly, so Claude/Ollama can emit useful built-in parameter moves instead of only Serum/Vital/Phase Plant style names.

## Why this matters

External AU automation is still limited by what the plug-in exposes to the host. Stock LemmingsStudio synths do not have that limitation. The agent can mutate the live instrument directly through the engine-side instance, so stock synths are now the reliable baseline target for agentic sound design.

## Untouched areas

- Splice MCP/download/preview code was not touched.
- Arrangement clip resizing was not touched.
- Voice AI recording was not touched.
