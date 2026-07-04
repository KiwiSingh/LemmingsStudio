# Buildfix 194 — Stock Device Audit / No Transparent Audio Stubs

This pass audits the stock-device browser after the Pattern Arp / Beat Stutter fix.

## Fixed

- Bit Crusher / Redux confirmed as active DSP: bit-depth quantization plus sample-rate hold/downsample.
- Added explicit active DSP for Mod Shaper.
- Added explicit active DSP for Voice Coder / Vocoder so it is audible without a sidechain carrier.
- Added a non-transparent stock audio fallback processor for any remaining stock audio-effect device that does not yet have a bespoke model.
- Mapped Spectral Time and Granulator away from generic BeatRepeat-only behavior into an audible character/time processor.
- External/CV bridge devices now use an explicit bridge pass-through object instead of accidentally falling into the generic fallback.

## Contract

Stock audio effects should never silently insert as transparent UI-only stubs. Racks, analyzers, and external/CV bridges can still be intentionally pass-through/control devices, but normal audio effects must either use their bespoke DSP or the audible stock fallback.
