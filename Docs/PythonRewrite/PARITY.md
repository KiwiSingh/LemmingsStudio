# Python rewrite: preservation contract and parity register

Baseline: `main` at `4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`, 26 October 2026.
Branch: `rewrite/python-windows`. Existing Swift and C# sources are retained.
The macOS application is the behavioral reference. A Python implementation replaces
neither product until every required row has Windows evidence against the unchanged macOS reference.

The new UI follows `Sources/LemmingsStudio/Views/ProDAWShell.swift` and the Liquid
Glass palette in `Views/LemmingsTheme.swift`. SwiftUI/AppKit APIs do not become
Python dependencies. Domain commands, persistence, jobs and presentation are split.
Native library dependencies handle device I/O, media decoding and vector DSP.

| Workflow | macOS reference | Python state | Required evidence before replacement |
|---|---|---|---|
| Native documents and unknown data | App/ProjectDocument.swift | New format and transactional edits implemented | Save/reopen/undo, failure preservation, unknown fields, backups |
| Existing project migration | App/ProjectDocument.swift, App/App.swift | Pending; legacy formats cannot be overwritten | Representative real projects; embedded samples, IDs, devices, routing and explicit reports |
| Arrangement and clip editing | Views/Arrangement.swift | Basic create/move/resize/duplicate/delete implemented | Selection, drag/snap, trim/split/consolidate and cross-platform round trips |
| Piano roll and theory | Views/PianoRoll.swift, Theory/Theory.swift | Basic note editing implemented | Velocities, note lengths, chords, scale/key snap, quantize and MIDI import/export |
| Step sequencer | Views/StepSequencer.swift | Basic 16-step pattern implemented | Layers, controller maps, per-step controls, print and preset restore |
| Session launcher | Views/ProDAWShell.swift | Pending | Independent launches, scenes, quantization, stopping and project recall |
| Transport, playback and export | Audio/AudioEngine.swift, Audio/Export.swift | Shared block renderer and WAV export implemented | Tempo maps, loop/seek, metronome, tails, effects, stems and alignment |
| Mixer, routing and automation | Views/Mixer.swift, Audio/Automation.swift | Gain/pan/mute/solo implemented | Sends, returns, buses, master, groups, parameter and tempo automation |
| Recording and MIDI hardware | Audio/Recording.swift, Audio/MIDIInput.swift | Pending | Dry recording, monitoring, latency, comping, overdub/replace and device changes |
| Stock instruments and effects | Instruments/, Effects/ | Five basic voices only; catalog pending | Original device settings/presets and listening/parameter/state fixtures |
| Plugins and VoxGarden | Plugins/, Bridge/ | Pending | Windows VST3 and macOS AU/VST3; isolation, latency and independent state recall |
| Warp, freeze and recovery | Audio/Warp.swift, App/App.swift | Pending | Source-preserving edits, freeze/unfreeze, autosave recovery and missing media |
| AI and stem workflows | Generative/ | Pending | Provider/runtime substitution, job preview/cancel/undo, model failure and offline operation |
| Splice and library | Generative/SpliceMCP.swift, App/App.swift | Basic audio import only | OAuth handoff, search/download rights, progressive indexing and relinking |
| Themes, settings and accessibility | Views/LemmingsTheme.swift, Views/SettingsView.swift | Default palette and responsive docks implemented | Theme persistence, keyboard navigation, scaling and small-display interaction |
| Distribution | build.sh, Ports/Windows/ | Pending | Self-contained builds, source/license bundle, signed installers, upgrades and uninstall preservation |

## Execution order

1. Verify the document/edit/audio contracts and the Windows workspace against the macOS reference.
2. Collect real project fixtures and audible reference renders from the retained macOS build.
3. Port arrangement, MIDI, mixer and recording workflows against those fixtures.
4. Add stock DSP and isolated plugin workers, preserving parameter and preset contracts.
5. Port remaining AI/library workflows with cancellable provider-neutral jobs.
6. Package and test side by side, then evaluate replacing the Windows build only after parity evidence.

Each feature gets a behavioral specification and a reference fixture. A green build,
a source file, a matching-looking screen, and a passing headless test do not establish
full usability or audio parity. The x64 UTM VM is a compatibility environment;
performance and live audio also need native Windows hardware.
