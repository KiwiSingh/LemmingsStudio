# Original melodic instrument parity — first sound milestone

Reference: `4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`, actual
`Instruments.swift` and `DSP.swift`. macOS application DSP is unchanged.

## Implemented

- Native C++20 original AnalogSynth: sixteen voices, allocation/stealing order,
  PolyBLEP oscillators, four waveforms, detune/mix, state-variable filter,
  ADSR, velocity, pitch bend and original output saturation.
- Native original GuitarInstrument/KarplusStrong: per-note string state,
  excitation, damping, retrigger and release. This is the existing synthesized
  guitar, not the subsequent sampled-guitar expansion.
- Allocation at instance creation; block rendering and note events allocate no
  memory. Thin Python interface validates inputs and owns independent instances.
- Shared MIDI clips render with their start, velocity and length. Playback and
  WAV export use the same native instruments, followed by the original limiter.
  Unsupported processors, plugin targets and routing still fail explicitly.
- Existing analog-family device parameters drive the native synth and survive
  `.lemmingsproject` save/open. Rack cards identify available native processing.
  In the reference Mac application thirteen registry names map to AnalogSynth;
  these ports preserve that mapping, not thirteen distinct synthesis engines.

## Evidence and tolerances

`Tests/ProjectCompatibility/main.swift` compiles the actual Swift instrument
classes and emits reference audio at 44.1/48/96 kHz. Five analog profiles cover
all waveforms and changed envelopes/filter/mix. Event sequences cover overlapping
notes, retrigger, stealing, bend, release and all-notes-off. Native blocks of 128
and 511 frames compare within absolute `3e-6`, relative `3e-5` float tolerance.
Independent runs and ordinary block partitioning are also checked exactly.

The Mac guitar uses unseeded random excitation and dictionary iteration. The test
harness captures the actual excitation using reflection, without changing product
code; native decay is compared using those same samples. Tiny summation-order
variation is covered by the stated float tolerance. Windows production excitation
uses a fixed deterministic seed, ensuring repeatable export and reopen; it does
not claim bit-identical random attacks to independently generated Mac audio.

Project tests verify note position, parameter audibility, silent gain, preserved
state, repeatable reopen/export and rejection of unavailable third-party targets.
The installed-app checker additionally renders/reopens both instruments and
writes actual WAV evidence. CI transfers actual Mac fixtures to Windows and
compares the Windows native binary against them.

## Gates still open

This is a completed instrument slice, not completion of the entire sound/engine
milestone. Live native graph/WASAPI/ASIO, hardware MIDI/MPE, low-latency monitoring,
recording, automation, effect chains, routing/delay compensation, remaining stock
instruments/effects and VoxGarden remain required. Current playback precomputes
session audio in a background job. No hardware latency or performance claim is
made. UI presentation still requires the remaining workspace acceptance tasks.

To reproduce: use the external-drive environment and native build, export Swift
references, then set `LEMMINGS_SWIFT_INSTRUMENT_REFERENCE` to the emitted
`instrument-reference` directory alongside the existing drum/fixture variables.
Run the full Python tests. Windows CI performs the same comparisons.
