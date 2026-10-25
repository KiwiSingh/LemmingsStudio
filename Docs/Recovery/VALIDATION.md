# LemmingsStudio implementation report

26 October 2026

## Result

Implemented an additive native development preview and portable plugin prototypes. **The complete product roadmap is not finished.** The old Windows and Swift macOS application source trees remain available. No production installer or Windows certification is supplied.

Local implementation branches:

- LemmingsStudio: `recovery/native-studio`, based on `4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`.
- VoxGarden: `integration/windows-dsp`, based on `8ab73f3a123a92655f5d340183a91f9a01848152`.

The source changes are present in this workspace under `work/LemmingsStudio` and `work/VoxGarden`. The downloadable source bundle contains the new files and patches; it excludes build products and external dependencies.

## Implemented

| Area | Current behavior |
|---|---|
| Windows replacement foundation | C++20/CMake/JUCE application target; native audio selector; block playback; reference MIDI melody; dry input recording and monitoring; audio import and dry WAV export |
| Project integrity | Versioned native JSON; temporary-file verification; backup on replacement; partial legacy import preserving original raw data and explicit warnings |
| Safe editing | Track-scoped transpose preview/apply/undo; stale proposals and unsafe undo are rejected |
| VoxGarden | VST3 loading/editor opening in native preview; Windows DSP platform patch; neural availability guarded; existing IDs/state contracts retained; pinned build script |
| Amp | Original six-family waveshaping prototype with drive, tone and gain; VST3/AU/standalone products; persistent parameters |
| Guitar and drums | Separate sampler plugin prototypes with verified pack loading, velocity mapping, round robins, sample-offset MIDI, note releases/pitch bend, drum choke groups and hi-hat CC4 switching |
| Plugin scanning | Disposable scan process; supervisor timeout; persistent quarantine and explicit retry |
| Delivery preparation | Windows/macOS CI definitions; dependency/content register; content manifest example; research protocol; roadmap and open-work register |

## Validation actually run

Environment: Apple Silicon arm64, macOS 27.2, JUCE pinned at `f72bad64d29715216226685810c5196bd0d79d77`.

- Full native application and amp/guitar/drum VST3, AU and standalone targets: built successfully on this Mac.
- Native CTest suites: **2/2 passed**. These cover session persistence and legacy preservation, invalid state rejection, scoped edit/undo, block-size-independent rendering, WAV length, bounded amp output, sample checksums, sample-offset starts, round robins, velocity layers, hi-hat switching, plus discovery/instantiation/finite processing/state restore of all three plugin wrappers.
- Python scanner tests: **2/2 passed**, covering timeout quarantine and crash quarantine.
- Actual amp VST3 scan through the separate-process supervisor: passed, exit code 0, not quarantined.
- Patched VoxGarden VST3 and check target: built successfully on this Mac.
- VoxGarden DSP/state CTest: **1/1 passed**.
- Patched VoxGarden discovery, instantiation, processing and state restoration through the native test host: passed.
- Changed-text whitespace checks and integration patch reverse-application checks: passed.

These results do not establish Windows compilation, Windows hardware performance, Ableton/REAPER compatibility, listening quality or legal clearance. CI definitions were added but were not run on GitHub during this session.

## Important limitations

The native UI currently lists session tracks; it does not provide the completed editable arrangement/piano roll/mixer/automation environment. MIDI playback uses a reference sine voice. Recording is a separate dry-input workflow, not simultaneous multitrack playback/recording. Long audio files need streaming support.

Plugin playback remains in-process. The preview loads VoxGarden manually as a master effect; per-track stock insertion, project context transfer, persistent plugin state, render-return alignment and plugin delay compensation are pending. Export intentionally prints the dry session and excludes preview effects.

No cleared factory guitar samples, drum kits, cabinet IRs, captures or neural weights are bundled. The sampler prototypes therefore require a separate approved pack and are not finished stock instruments. The amp still needs its pedal chain, cabinet convolution, oversampling, effect ordering and curated presets. String-aware guitar performance, richer articulations, drum mic mixing, multi-output and grooves remain pending.

Creator interviews, full migration/recovery, AI provider jobs, resumable content downloads, Windows neural parity, installer signing, external-host testing and the Windows 32-track/60-minute hardware soak remain open.

## Continue implementation

Use `Docs/Recovery/ROADMAP.md` for milestone order and `Docs/Recovery/IMPLEMENTATION_STATUS.md` for open work. Next gates are Windows CI/hardware bring-up, a complete record/edit/save/reopen/export vertical slice, and cleared instrument content. Do not retire the old Windows build or label this preview production-ready.
