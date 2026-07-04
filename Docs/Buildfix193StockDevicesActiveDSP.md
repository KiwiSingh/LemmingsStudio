# Buildfix193 — Stock Devices Active DSP/MIDI Processing

Fixes a regression where some stock devices were effectively UI shells or were processed with stale timing/parameter state.

## Fixed

- Pattern Arp is no longer a simultaneous octave-doubler/no-op.
  - MIDI clips now generate arpeggiated note ticks across the held note span.
  - Arp timing is block-safe, so notes that start before the current audio block can still produce arp ticks inside the block.
  - Rate, octaves, and gate are respected.
  - Arp scheduling uses musical beats, not one-shot note-start scheduling.

- Beat Stutter / Beat Repeat now follows project tempo.
  - The old implementation converted beats with a fixed `0.5 * sampleRate` assumption, which effectively hard-coded 120 BPM.
  - It now receives the live transport tempo through a `TempoAware` stock-device hook.
  - Interval and grid parameters are converted from beats to samples using the current BPM.
  - The stutter buffer captures prior audio and repeats slices on the configured musical grid.

- Stock device parameter changes now reach live DSP reliably.
  - Track device DSP mirrors are re-synced from their `DeviceModel.params` during processing.
  - This prevents rack controls from looking changed while the audio thread keeps using stale values until a rebuild.
  - Clip insert FX also receive tempo/parameter sync before processing.

## Files changed

- `Sources/LemmingsStudio/Effects/Effects.swift`
- `Sources/LemmingsStudio/Effects/StockDSP.swift`
- `Sources/LemmingsStudio/Audio/AudioEngine.swift`

## Notes

`swiftc -parse` passes for the edited audio/effects/sequencing files. A full Linux `swift build` still hits the existing resource-copy issue for the bundled `Resources/StemBackends` directory, which is unrelated to this patch and not representative of the macOS/Xcode app build.
