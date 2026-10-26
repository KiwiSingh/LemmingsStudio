# Windows parity implementation and acceptance

Baseline: `4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`.
Windows: Python + custom Qt Quick + a C++20 audio engine. macOS stays Swift;
changes there are confined to document compatibility. Neither the existing Qt
Widgets preview nor its `.lemmingspy` format is an accepted replacement.
All active local development and artifacts belong on Zweidrive. Main is unchanged.

## Reference and evidence

`mac-reference.json` inventories 49 Swift sources, 94 registry entries and 26
resources. Reproduce it with `python tools/inventory_mac_reference.py`.
This is source evidence, not an assertion that every Mac registry entry works.
Before acceptance, record the packaged Mac revision, all seven workspaces, all
eleven themes, contextual controls, presets, interaction tasks and audio outputs.
Every row needs observed Mac behavior, Windows implementation and acceptance evidence.

## Ordered delivery gates

1. **Shared projects:** one `.lemmingsproject` reader/writer, v1/v2 read, shared v3
   identity and state, embedded/portable media, unknown-field retention, safe saves,
   previews imported once without overwriting originals. Real bidirectional tests.
2. **Startup and presentation:** actual MagmaVance video/refresh variants,
   Lemmings splash and opening WAV; original timing and voice trigger; every Mac
   theme and design token. Qt Quick software rendering and error diagnostics.
3. **Sound and engine:** exact algorithms, presets, parameters and voice mappings
   for all stock instruments/effects. Native transport, WASAPI/ASIO, MIDI/MPE,
   graph, recording, routing, automation, compensation and shared offline rendering.
4. **Editing:** Session, Arrangement, Piano Roll, Step Sequencer, Devices,
   Automation, Mixer, browsers, theory, generators, inspector, keyboard/focus,
   drag/drop, menus, undo/redo, scaling and multi-monitor behavior.
5. **Production:** capture/monitor modes, tempo, metronome/count-in, sends/groups,
   sidechains, warp algorithms, freeze, export formats/depths/channels, recovery.
6. **Plugins/integrations:** isolated VST3 scanning/hosting, replacement of missing
   third-party slots without losing state, AI agents/chat/sound design, Splice,
   libraries, stems, voice workflows, desktop bridge, controllers and Discord.
7. **VoxGarden:** required integrated device, as specified below.
8. **Release:** real Windows desktop launch, native hardware performance,
   32-track reference session, 60-minute soak, signed installer, upgrade/rollback,
   missing-dependency handling and uninstall project preservation.

The later sampled guitar, amp and rock-drum expansions remain on the roadmap;
they do not replace faithful ports of the existing stock devices.

## VoxGarden contract — supersedes external-host wording

The existing KiwiSingh/VoxGarden repository and its local changes remain untouched.
A clean snapshot of upstream commit `8ab73f3a123a92655f5d340183a91f9a01848152`
is isolated in a separate integration repository. Preserve AGPL, authorship and
all dependency/content notices. Do not include unrelated uncommitted changes.

The integrated edition runs inside LemmingsStudio only. No external VST3/AU or
standalone installer is delivered by this work. Existing upstream distribution
is not changed. Keep device code native and reuse its editor, DSP, 24-voice
behavior, presets, score/lyrics workflows, appearance and state identifiers.

Implementation sequence:

- Build an application-private native device target from the pinned source;
  exclude external format wrappers from the integrated build. Use the host's
  device-worker boundary rather than loading a separately installed plugin.
- Register VoxGarden in the stock browser/rack, with insertion on the selected
  audio track, its original editor and independent per-instance recall.
- Explicitly transfer selected MIDI, lyrics, root/scale and tempo; do not mutate
  other instances or silently consume unrelated project material.
- Save versioned processor/editor/score/lyrics state inside `.lemmingsproject`.
  Models are shared immutable downloads, not shared musical state. Store model
  identifiers, revision/checksum and render provenance with recoverable results.
- Report actual processor latency to the graph. Compensate playback and printing;
  offer dry recording/monitoring rather than promising zero-latency choir effects.
- Capture and print on worker jobs, retain source on cancellation, and insert the
  mix and stems at their originating timeline position, including silent stems.
- Deliver validated Windows DSP first. Port Apple-only neural paths to compatible
  Windows runtimes in the same required workstream; do not call neural parity
  finished until the actual models, languages, score timing and voice rights pass.
- Audit redistribution rights separately for code, models, voices and references.
  Missing models leave DSP functional. Model failure or offline use cannot corrupt
  the session. Provide progress, cancellation, checksums and storage controls.

Acceptance: multiple independent instances; original parameter compatibility;
Windows/macOS project round trips; correct latency/alignment; capture cancellation;
missing/corrupt models; offline DSP; editor reopening; original sound comparisons;
worker crash recovery; repeatable rendering. A pinned source snapshot is not
implementation completion.

## Current verified work, and explicit limits

Implemented in this change:

- Swift v3 stable IDs for tracks, clips, notes, devices, layers, sends, groups and
  external slots; group routing, selected drum kit, multi-hit step patterns, freeze
  state, master effects, global swing and channel settings persisted.
- Swift unknown fields retained by identity when reordered; clearing an optional
  known field does not resurrect old state. Legacy v1/v2 decoding retained;
  unsupported future versions rejected.
- Independent Python lossless contract boundary with safe replacement/backups,
  stable migration, identity checks and unresolved legacy-reference diagnostics.
- Versioned native C ABI and an offline faithful port of all ten `DrumVoice`
  algorithms. Sixty numerical comparisons use actual Swift renders (three rates,
  two parameter profiles), including kick versus sub identity and cymbal tails.
- An actual Swift → Python edit/save → Swift read/save → Python check, plus
  Windows CI comparisons against the same Mac-generated fixtures.

Historical status before the workspace phase: canonical project integration into the preview UI, all other
omitted musical state, sample-layer portability, unavailable-device placeholders,
Qt Quick/branding integration, live native audio graph, all other stock DSP,
production workflows and VoxGarden device integration. The old preview renderer
still exists; this change does not certify it or ship it as full parity.

Full Mac app compilation currently encounters an existing unrelated error in
App.swift's audio-signature prompt (`AudioClip.lengthBeats` does not exist).
The compatibility harness compiles the real document/model/DSP sources without
that application entry point. Passing it is not a full application build.

## Reproduce local validation

Source `/Volumes/Zweidrive/LemmingsStudio/environment.zsh` first.
Set `LEMMINGS_TEST_OUTPUT` to an external artifact directory and run
`sh Tests/ProjectCompatibility/run.sh`, then use the same variable with
`python Tests/ProjectCompatibility/round_trip.py`.

Build `PythonStudio/native` with CMake into an external directory. Set
`LEMMINGS_NATIVE_LIBRARY` to its library, `LEMMINGS_SWIFT_FIXTURE` to the emitted
`swift.lemmingsproject`, and `LEMMINGS_SWIFT_DRUM_REFERENCE` to `drum-reference`.
Run `QT_QPA_PLATFORM=offscreen python -m pytest PythonStudio/tests -q`.
The `Mac and Windows parity contracts` workflow repeats the real Swift reference
and Windows native comparisons. Headless tests do not certify desktop launch.

## Startup phase implementation

The original eleven branding assets are staged by checksum from the Mac reference.
A lightweight entry records launch events before importing Qt or audio. Qt Quick
renders the original video/artwork and text; media initialization and audio-library
preloading follow the first frame. The original WAV plays in normal launches.
Software rendering is explicit and receives one retry on a reported scene-graph
failure. Decode failures advance to the splash/workspace and leave diagnostics.

The Windows bundle and installed application both have a real `windows` platform
check: original video frames and WAV samples decode, the splash sequence finishes,
and the existing workspace becomes visible. Audio output is suppressed in checks.
Phase timings, screenshots and log paths are retained. This verifies startup,
not all-workspace appearance, native hardware sound, cold-launch performance or
full Windows parity. Exact platform blur/shadow/typography comparison remains part
of visual acceptance; the original artwork is unchanged.

## Workspace phase

Normal startup now opens the Qt Quick workspace and edits the shared project
directly. All seven pages, original themes, drum kit and master limiter are
implemented/tested to the extent recorded in [WORKSPACE_UI.md](WORKSPACE_UI.md).
That ledger supersedes the earlier UI-pending statements above. Full workspace
and backend acceptance remains open; it lists the outstanding interactions.
