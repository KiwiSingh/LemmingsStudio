# Stock sound parity implementation and acceptance

Reference: Mac source `4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`.
This phase replaces the Windows audio restrictions with original native stock
processing. Main and the upstream VoxGarden repository remain untouched.

## Implemented audio paths

- Every existing source track kind: Analog Synth, Guitar, drums/sequencer,
  Indian Percussion/Bhangra Dhol, Bhangra Architect, Oscillatron, LemmingBass,
  2C, Bailaton, Dubstep Wrangler and embedded recorded audio.
- Oscillatron's twelve voices, moving fold, three oscillators/sub; LemmingBass's
  mono retrigger/click/filter/drive; twelve modal Indian strokes, overlapping-hit
  limits and Bhangra's original tumbi/reed voices. Prior Analog/Guitar/drum ports
  remain in use. 2C uses Guaracha; Dubstep Wrangler uses the Dubstep drum kit,
  exactly as the actual Mac track factory does. Its unused standalone wobble
  class is not substituted for every drum lane.
- All 48 post-instrument audio/analyzer registry entries, representing 28 native
  processor families. See `STOCK_SOUND_COVERAGE.json` for every registry entry.
  The Mac deliberately shares delay/reverb/saturation/character processors across
  some names; Windows preserves that dispatch. These are original stock effects,
  not the later expanded sampled guitar, amp and rock-drum products.
- Native 32-/48-voice sample-layer mixers with replacement-note routing, original
  velocity/level behavior, clipping and voice limits. The original Mac one-shot
  path plays source frames without resampling; this behavior is preserved.
- Original Beat OLA, Complex phase vocoder and Complex Pro phase-lock algorithms.
- Worker-side project graph: clip/track effects, per-device mono/bypass,
  linear automation, MIDI transformations/arp, tempo-map lookup, group controls,
  compressor sidechains, pre/post sends, returns, master chain, frozen audio,
  pitch/trim/loop/gain and original linear pan law. Playback/export share it.
- Arrangement/Piano Roll and live Step scopes are isolated, preventing duplicate
  grid/printed-clip hits. Built-in/sample routing notes are not transposed by a
  lane's octave control. Non-step tracks cannot bleed into Step playback.
- Working native metronome voice; project render tail for UI export; freeze and
  unfreeze with undo. Freeze commits only if the source track is unchanged.
- Background replacement renders make edits audible without stopping the writer;
  valid updates switch at a block boundary with a short crossfade. Obsolete or
  failed updates retain current playback. Rendering and export are cancellable;
  cancellation retains source state and the export destination.

## Shared one-shots

`sequencerLayers[].embeddedSamples` is an optional v3-compatible mono payload.
Windows Save/Save As embeds referenced local one-shots without overwriting their
source files or provenance paths. Mac's document writer embeds available samples;
its reader/source selection reads the same payload. These narrow Swift changes
are solely for portable-project compatibility; synthesis/effect algorithms are
unchanged. Paired-release round trips retain embedded content even when the
original path is unavailable. Missing unembedded samples raise an explicit error
on Windows rather than silently substituting a drum voice.

## Numerical evidence

The real Swift classes generate fixtures at 44.1/48/96 kHz. Effects use two
parameter profiles, distinct stereo signals, impulses and a silent tail; native
comparisons allow absolute `4e-6` / relative `4e-5` float tolerance. Source tests
exercise stealing, retriggers, bends, panic, envelopes and overlapping sample
voices. All three warp modes compare against actual Swift output at three
stretch ratios. Existing original Analog/Guitar/drum/limiter tests remain.

IndianPercussion's only `Float.random` call is replaced by a seeded noise call in
an external test-source copy. `noise-oracle.json` records its source checksum and
instrumentation. Product Swift synthesis is untouched. This tests the complete
modal/noise envelope deterministically, not identical independent random attacks.
The guitar oracle still captures actual Swift excitation. Windows seeds preserve
repeatable renders/reopens. No stochastic bit-identity claim is made for Mac's
unseeded production attacks.

Some original effects copy left filter state to right or rebuild/reset filters
on each host block. Oscillatron advances its shared morph phase per voice/block.
These quirks are preserved and tested using explicit block sizes; do not claim
arbitrary host-buffer partitioning is bit-identical. Windows's worker graph uses
128-frame processing quanta. The Mac's actual AVAudioEngine scheduling can pull
MIDI events to a block boundary; numerical device parity is not a whole-session
sample-identity claim across different host buffer sizes.

Registry racks are transparent in the reference Mac implementation. MIDI slots
are transparent to audio but their scheduling rules are implemented. External/CV
bridges require real endpoints and remain unavailable, with state preserved;
transparent Mac registry shells are not counted as functioning external hosting.

## Remaining full-product acceptance gates

This completes a broad stock-DSP/rendering pass, not a declaration of full Windows
product parity. Live WASAPI/ASIO native graph, input recording/monitoring, hardware
MIDI/MPE, plugin isolation/hosting, delay compensation, multichannel endpoints,
compressed export/metadata, long-session streaming/performance, and app-bound
VoxGarden remain required. Playback currently prepares native audio on workers
and writes through the existing blocking output worker; there is no Python audio
callback, but this is not the final low-latency native transport.

The installed checker exercises all twelve instrument kinds and all 48 effect
entries, saves/reopens projects and writes WAV evidence. Windows CI compares its
native binary to Mac fixtures and checks install/launch/reinstall/uninstall.
Native Windows listening, device-driver tests, the 32-track performance session
and 60-minute soak remain mandatory. UTM cannot certify latency or hardware I/O.
The unrelated existing full Mac app compile error remains documented separately
from the compiling real-model/DSP compatibility harness.

## Reproduce

Use the Zweidrive environment and build directory. Export Swift references with
`Tests/ProjectCompatibility/run.sh`; run `round_trip.py`. Set the native library
and Swift fixture variables plus `LEMMINGS_SWIFT_EFFECT_REFERENCE` (`effect-reference`),
`LEMMINGS_SWIFT_INSTRUMENT_REFERENCE` (`instrument-reference`),
`LEMMINGS_SWIFT_WARP_REFERENCE` (`warp-reference`) and existing drum-reference path.
Run the complete Python suite and installed-app startup check. CI repeats these
comparisons on Windows. All local environments, caches and evidence stay external.
