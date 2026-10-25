# LemmingsStudio product recovery and implementation roadmap

Baseline: 26 October 2026. Primary audience: general AI music makers. Preserve the Swift macOS application; replace the Windows application alongside the old port. Continue open-source distribution with explicit GPL/AGPL compliance. VoxGarden Windows DSP precedes neural parity. Guitar and amp are separate linked products. Rock drums begin with samples.

## Product evidence and independent development

Validate these hypotheses with 8–12 creators: setup friction, hard-to-edit generated audio, unpredictable assistant edits, fragile plugin/model dependencies, repetitive stock instruments and platform-specific project failures. Observe installation, creation, AI editing, recording, revision and export. Record task completion, time, errors and workarounds. Do not label hypotheses as completed research.

Study Suno Studio's MIDI/stem workflows, ACE Studio's MIDI/lyrics and DAW bridge, and RipX's stem/note editing. WavTool is historical context. FL Slayer informs the instrument-plus-amplification workflow; MODO DRUM informs expressive kit customization, not a promise to copy physical modeling. Implement original code, interfaces, presets and artwork. No competitor assets enter the product.

## Ordered milestones

| Milestone | Deliverables | Exit gate |
|---|---|---|
| 0 Establish truth | Pinned revisions, source/project inventory, ranked backlog, dependency/content register, user interviews | Reproducible baseline and documented research results |
| 1 Foundation | C++20/JUCE Windows shell, audio devices, block audio/MIDI playback, recording, VST3, persistence/export | Record → edit → save → reopen → export on real Windows hardware |
| 2 VoxGarden | Application-managed stock insertion, external installers, Windows DSP, context transfer, aligned returns, per-instance state | Ableton/REAPER/Lemmings session recall and alignment validated |
| 3 Core parity | Arrangement, piano roll, sequencer, mixer, routing, automation, recovery, full project migration | Representative projects migrate with explicit compatibility reports |
| 4 Guitar and amp | Cleared DI/acoustic content, expressive guitar, six amp families, pedal/cabinet chain, 40 presets, linked racks | Musical listening, live-input and host tests pass |
| 5 Rock drums | Cleared kit, articulations, round robins/velocity, e-drum mapping, mic mixing, multi-output, original grooves | Repeatable exports, hi-hat control and choking validated |
| 6 AI workflows | Typed scoped proposals, review/apply/undo, provider jobs, progress/cancel, stems, project context | Failure/cancellation cannot corrupt source material |
| 7 Release | Windows hardware matrix, clean installs/upgrades/rollback, signing, recovery, performance | No unresolved release blockers |

Dependencies: milestone 0 informs every release; milestone 1 underpins milestones 2–6. No calendar commitments before staffing, Windows hardware and recording needs are known.

## Implementation contracts

- Separate session state, editing commands, audio processing, UI and background jobs. Shared processing implementations have VST3/AU wrappers; standalone VoxGarden remains available.
- Never perform downloads, model inference, file access or sample decoding in the audio callback. Playback/export must converge on the same graph with latency compensation before production release.
- Version session and parameter state. Preserve old projects unchanged; unsupported migration fields must be retained and reported, not silently dropped.
- Scan plugins in disposable processes; add runtime workers, timeouts, quarantine and recovery before production certification.
- VoxGarden keeps existing identifiers/parameters. Explicit context transfer includes root/scale, tempo, MIDI and lyrics; render returns include origin and timeline alignment. Share model files, not instance state. Offer dry recording around its substantial DSP latency.
- Guitar: flagship electric DI, additional steel/nylon, sustain/palm mute/dead notes/releases/slides/harmonics where recorded; string-aware voicing, picking, strums, bends/vibrato and MIDI learn.
- Amp: gate/pedals/preamp/power amp/cabinet/EQ/modulation/delay/reverb, reorderable effects, calibration, oversampling and live/render quality. NAM is a later expansion with independently cleared models/IRs.
- Drums: one complete rock kit first, velocity/RR, hi-hat openness/chokes, tuning/envelopes/gain/pan, genuine recorded mic channels, stereo/multi-output, GM/editable maps and seeded humanization.
- Core installer stays small; content/model packs are optional, checksummed and resumable. Target Windows 11 x64 first; ASIO requires verified licensing. ARM64/Linux/advanced audio-note editing/physical drums remain later work.

## Content and license gate

Record source URL, pinned revision, SHA-256, license, attribution, redistribution basis and approval for every shipped dependency/asset. Check code, samples, mappings, model weights and voice references separately. Permission to publish songs does not establish permission to bundle raw samples. Candidate packs stay out of binary releases. Commission missing DI/kit recordings only under written redistribution rights.

LemmingsStudio GPLv3 and VoxGarden AGPLv3 notices remain distinct. JUCE's AGPL/commercial options and combined-work distribution need review. Source presence or a manifest flag does not constitute legal approval. Review specific patent/trademark questions before release.

## Acceptance matrix

Test 44.1/48/96 kHz and multiple buffers, device changes, recording underruns, MIDI timing and plugin delay compensation. Test old-project imports, save/open repetition, autosave, missing content/plugins and crashes/hangs. Test guitar articulations/strum timing and drum round robins/chokes/CC4. Test offline operation, model failures, cancelled jobs and interrupted downloads. Test clean installs, upgrade/rollback/uninstall preservation. Test Ableton Live and REAPER on Windows/macOS.

Define a Windows reference machine and fixed 32-track workload. Require a 60-minute uninterrupted playback/recording soak at documented settings. Publish actual measurements. Every released feature needs reproducible builds, cleared assets, persistent state, meaningful test evidence and explicit limitations.

## Current implementation evidence

See `IMPLEMENTATION_STATUS.md`. The native foundation is an additive development preview, not a certified Windows replacement. All external/hardware/research gates remain open until evidence is recorded.
