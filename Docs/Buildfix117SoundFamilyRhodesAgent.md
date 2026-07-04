# Buildfix117 — Sound Agent Rhodes / Electric-Piano Family

This build fixes a Sound Agent classification hole where prompts such as:

> Create me a rhodes-style piano

could bypass the Serum/static synth recipe because the natural-language parser did not treat `piano`, `Rhodes`, `Wurli`, `e-piano`, or `tine` as synthesis intent. The result could be nearly identical to Init.

## Changes

- Added a dedicated `electricPiano` sound family to the agentic sound translation layer.
- The parser now recognizes Rhodes / Wurli / electric piano / e-piano / epiano / tine / FM piano language as actionable synth-design intent.
- Added a deterministic Rhodes-style recipe:
  - sine/triangle-ish oscillator body
  - small octave-up tine layer
  - low resonance
  - medium cutoff
  - percussive attack
  - medium decay
  - low sustain
  - playable release
  - chorus
  - subtle tremolo / amp-LFO hints
  - subtle room and very low delay
- Added electric-piano guardrails so generic model output cannot leave the patch close to Init.
- Added extra alias matching for tremolo / amp-LFO style controls in hosted AU/VST-style synths.
- Updated the stock analog fallback so built-in synth targets also get a Rhodes/Wurli-like patch instead of generic keys.

## Files changed

- `Sources/LemmingsStudio/Generative/Agents.swift`
- `Sources/LemmingsStudio/Generative/DeviceTranslationLayer.swift`
- `Sources/LemmingsStudio/Generative/Generative.swift`
- `Sources/LemmingsStudio/Plugins/AUHosting.swift`

No Splice, stem splitting, mixer drag/drop, metronome/count-in, or Arrangement workflow code was changed.
