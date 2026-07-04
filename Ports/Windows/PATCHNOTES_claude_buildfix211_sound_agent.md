# LemmingsStudio Windows — buildfix211 (Claude): SoundAgent (text → synth patch)

Ports the macOS sound-design agent so the AI can dial in an instrument from a text description,
closing the last major gap with the Mac generative stack.

## `Features/SoundAgent.cs`
- **DesignAsync(description, targetDevice, model)** — asks Ollama for `{presetName, notes,
  params}` and applies the values to an instrument `DeviceSlot`.
- **Deterministic heuristic baseline** — the Mac's keyword→sound vocabulary
  (bright/dark/warm, pluck/lead/pad, bass/sub/808, supersaw/detuned, acid/resonant, 80s/
  synthwave, …) ported and mapped into the Windows instruments' **normalized 0..1 controls**
  (Cutoff, Drive, Detune, Sub, Resonance, Punch, Wave). This runs first, so offline or
  garbage model output still yields a musical patch; the LLM only overrides.
- Only parameters the target instrument actually exposes are touched (case-insensitive match),
  and a real patch name is derived (never the raw prompt).

## AI tab
- New **Design Sound 🎛** button: designs the instrument on the track named in the prompt (or
  the first instrument found), applies the patch, prints the preset name + notes + changed
  params, and refreshes the Devices tab so you see the sliders move.

## Honest scope
- The Mac SoundAgent drives AU/Serum targets in Hz/seconds with a deep parameter-translation
  layer; the Windows port maps the same descriptive intent onto our built-in instruments'
  normalized controls (no AU/Serum hosting in the offline engine), so it's a faithful port in
  spirit rather than a 1:1 parameter clone.
- Authored on Linux without the .NET toolchain — brace-balanced, standard System.Text.Json;
  expect at most minor fixups on first Windows build.
