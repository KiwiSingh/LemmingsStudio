# Workspace UI parity ledger — 27 October 2026

Reference: Mac shell and view sources at baseline
`4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`, with the branch's narrow document
compatibility fixes. The existing packaged Mac application's revision/appearance
has not yet been reconciled. Main and the original VoxGarden repository stay
unchanged. This ledger records implementation, not full acceptance.

| Area | Reference | Windows work and evidence | Still required |
|---|---|---|---|
| Shell | `ProDAWShell.swift` | Custom Qt Quick transport, horizontal/vertical split panes, detail deck, browser/dock, status undo; 1024×768 and 1600×900 captures | Packaged Mac comparison, exact material/shadow/motion, scaling/multiple monitors/accessibility |
| Themes | `LemmingsTheme.swift` | All 11 exact sRGB palettes/glyphs, original background gradients/glows; Swift-export equality check | Native material equivalence and visual approval |
| Session | `SessionMatrixView` | Scene grid, clip/scene launch matching Mac's seek-and-start behavior, empty MIDI slot creation | Stop/context actions, full session interaction comparison |
| Arrangement | `Arrangement.swift` | Track/clip selection, MIDI creation, clip move/resize, waveform display, duplicate/delete/split, half-open loop repetition, playhead seek | Selection ranges, marquee, consolidation, full menus, drag/drop, warp/freeze controls |
| Piano Roll | `PianoRoll.swift` | Note draw/move/resize/delete, velocity, snap, quantize, zoom; actual mouse test | Full pitch range controls, multi-note selection, clipboard, generative/theory tools and contextual actions |
| Sequencer | `StepSequencerView` | 10 original drum lanes, 13 kits, simultaneous hits, 4–64 steps, audition, clear, atomic print; no hidden source switching | Full layer/source controls, per-hit velocity and musical generators |
| Devices | `DeviceRack.swift` | Original 94 registry entries/parameter definitions, normalized/log controls, bypass/mono/reorder/remove; unavailable plugin placeholders | Preset strips, drag/drop, MIDI learn, external hosting/replacement, complete native processors |
| Automation | `AutomationEditor.swift` | Original parameter ranges/log normalization, lane add/delete/enable, point add/move/delete, clip context, global tempo editor; portable state | Full waveform context, point selection keyboard commands, native playback |
| Mixer | `Mixer.swift` | Tracks, returns, sends, grouping, master strip/level; original default returns/limiter; saved bus state | Real live meters, routing graph, return/master device editing and drag/drop |
| Browser/dock | `ProDAWShell.swift` | Seven browser tabs and seven dock tabs, device search, import, track selection, fifths/key/triad | Service adapters, full libraries/search, all theory/chord tools and provider settings |
| Documents | `ProjectDocument.swift` | Normal UI uses shared `.lemmingsproject` exclusively; undo, atomic save/reopen, unknown state preservation | Full paired-release project fixtures and production recovery/streaming |
| Startup | Original resources | Existing original video/splash/opening sound retained | VM listening and native cold/warm launch measurements |

## Sound integrity

The Mac creates A Reverb, B Delay and a master Peak Limiter by default. Windows
now retains those defaults. The limiter and 24-slot drum kit are native ports,
compared against actual Swift renders at 44.1/48/96 kHz. Kit tests include 80
hits to exercise overlap, voice stealing and persistent RNG reuse. Original
one-shot tests cover ten voices and two parameter profiles. No generic fallback
instrument is used by the new workspace.

Other audible processors, nonzero sends/groups/external routing, automation,
swing, freeze, advanced layers, warp/pitch and non-stereo output remain explicit
rendering gates. State can be edited/preserved without implying its processor is
implemented. AI/Splice/voice buttons are unavailable pending their adapters.
VoxGarden remains a required later integration gate, app-bound and maintained
outside the untouched parent repository; no external DAW installer is produced.

## Reproducible evidence

- `PythonStudio/tests/test_quick_workspace.py`: actual Qt Quick mouse editing,
  small-screen drawer access, all page loads, all theme palettes, single-undo
  printing, split/duplicate/automation IDs, async shared save/reopen, refusal to
  substitute unsupported sound, and Swift-export equality.
- `PythonStudio/tests/test_native_audio.py`: original Swift/native DSP comparisons.
- `--startup-check-report`: real desktop launch, all seven pages at two sizes,
  eleven theme captures, shared-project edits and native audio export. QML errors
  fail this check; screenshots alone do not satisfy functional acceptance.
- Local evidence: `/Volumes/Zweidrive/LemmingsStudio/Artifacts/workspace-pass`.
  CI repeats installed Windows checks and publishes the validation artifact.

Next acceptance work is driven by the remaining column above. Full workspace
parity must not be marked complete until these interactions and packaged-Mac
comparisons pass. UTM is for compatibility; native Windows hardware remains
required for latency/performance and the long-session soak.
