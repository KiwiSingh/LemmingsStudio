# LemmingsStudio native foundation preview

This is an additive C++20/JUCE replacement foundation. The existing WinForms Windows port and Swift macOS application are unchanged. This preview is not the finished Windows replacement.

## Build

Requires CMake 3.24+, a C++20 compiler and platform SDKs. On Windows use Visual Studio 2022 Desktop C++ tools and Windows 11 x64. ASIO is disabled; JUCE's Windows device types provide WASAPI. Dependencies are pinned in CMake.

```
cmake -S NativeStudio -B native-build -DCMAKE_BUILD_TYPE=Release
cmake --build native-build --config Release --parallel 2
ctest --test-dir native-build -C Release --output-on-failure
python -m unittest discover -s NativeStudio/tests -p 'test_*.py'
```

An existing checkout of the pinned JUCE revision can be supplied with `-DLEMMINGS_JUCE_DIR=/absolute/path/to/JUCE`. Build output is under each target's `_artefacts/Release` directory. CI builds Windows x64 and macOS; passing CI is not hardware certification.

## Implemented preview capabilities

- Native audio/MIDI device selector, editable tempo and a reference MIDI melody.
- Block-based playback and matching dry WAV export. Source clips preload independently with a ten-minute per-file limit; long-file streaming is pending.
- WAV/AIFF/FLAC import, dry mono input recording with background disk writes, optional monitoring and disk-overflow reporting. Recording and session playback are separate in this preview.
- Versioned `.lemmingsnative` save/open, temporary-file verification and backup on replacement.
- Partial legacy Windows/macOS JSON import; original document retained in `legacySource`, with explicit unsupported-feature warnings. Legacy files cannot be overwritten through this save path.
- Scoped transpose preview, apply and undo. Stale proposals and unsafe undo are rejected. This is a deterministic command interface, not a connected AI model.
- In-process VoxGarden VST3 file loading/editor opening. Processing is a master preview effect; not yet a per-track stock rack, context bridge or persisted plugin state.
- Disposable-process VST3 scanning with Python timeout/quarantine supervisor.
- Original Lemming Amp prototype: six waveshaping families, drive, tone and output parameters; VST3/AU/standalone wrappers and state recall.
- Guitar/drum sampler plugin prototypes: checksum/provenance-gated sample loading, velocity ranges, round robins, sample-accurate note starts, pitch bend, note releases, pan/gain; drum choke groups and hi-hat CC4 switching.

## Explicit limitations

Do not replace a production DAW installation with this preview. Plugin playback is in-process, there is no plugin delay compensation, plugin context transfer or persisted plugin state, and WAV export excludes preview effects. The reference MIDI voice is a sine oscillator. Device changes during recording need hardware validation. Live hardware MIDI routing, editable arrangement/piano roll, routing/automation/warp, embedded legacy audio playback, content download manager, installer/signing and full recovery remain pending.

No guitar recordings, drum kits, captures, cabinet IRs or neural weights are included. Sample plugins require a separately cleared pack. `content/pack.example.json` is deliberately unapproved. Marking a manifest approved is a technical gate, not proof of legal rights; attach license evidence in the content register before distribution.

The amp prototype does not yet implement the planned pedal chain, cabinet convolution, oversampling, 40 curated presets or reorderable effects. The guitar does not yet provide string-aware voicing, strumming or articulation UI. Drums do not yet offer microphone mixing, multi-output buses, grooves or seeded humanization.

## VoxGarden Windows DSP

`tools/build-vox.ps1` checks out the pinned upstream VoxGarden revision into a new directory, applies the integration patch, fetches its pinned dependencies, then builds VST3, standalone and checks. It refuses to alter an existing checkout. The patch keeps plugin identifiers and parameter contracts intact, guards macOS-only process code, and disables unsupported neural jobs on Windows. Existing macOS AI parameter values are preserved in saved state while Windows DSP printing ignores unavailable AI processing.

## Scan supervision

```
python NativeStudio/tools/scan_plugins.py /path/to/LemmingsNative /path/to/plugin.vst3 --database /path/to/registry.json
```

A timeout or crash quarantines the plugin. Use `--retry` explicitly after an update. Scanning and runtime isolation are different: playback-worker isolation remains pending.

## Licensing

Existing LemmingsStudio GPLv3 source notices remain in force. This preview links JUCE under its AGPLv3 option; preserve both sets of notices and the combined-work obligations. VoxGarden remains AGPLv3 in its own repository. The content register records audit status and deliberately does not approve a public binary release. Review exact dependency notices and corresponding-source packaging before distributing builds.
