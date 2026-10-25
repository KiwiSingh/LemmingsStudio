# Recovery implementation status

This document distinguishes code from validated product behavior.

## Implemented in this change

- Additive NativeStudio C++20/CMake/JUCE foundation, preserving both shipping source trees.
- Versioned native session persistence, backup/temporary writes and partial Windows/macOS legacy import retaining raw source data.
- Block renderer, reference MIDI synthesis, source-file preload, dry WAV export, native audio selector and dry-input recording UI.
- Typed scoped transpose proposal/apply/undo with stale-state rejection.
- VST3 loading/editor preview and separate-process scan CLI; timeout/quarantine supervisor.
- Amp DSP prototype and VST3/AU/standalone products.
- Sample guitar/drum prototype products with checksum-gated content loading, note/velocity/RR mapping, choke and CC4 behavior.
- VoxGarden Windows DSP platform guards and deterministic source-patch build integration.
- Windows/macOS CI definitions, core/scanner tests, initial dependency/content register and creator-research protocol.

## Not completed

- Interviews, participant recruitment and ranked findings.
- Windows compilation/hardware certification until CI and real-device evidence exists.
- Full project migration, editable arrangement/piano roll, mixer routing, tempo automation, warp, latency compensation and long-file streaming.
- Plugin playback process isolation, stock per-track rack, persisted plugin state, VoxGarden project context and aligned result insertion.
- Cleared flagship DI guitar/acoustic/rock-drum content, guitar expression UI, mic mixes, drum multi-outs and original grooves.
- Full amp effects/cabinet/oversampling chain and curated preset collection.
- Model/content download manager, full AI providers/stem job integration, Windows neural parity, installer signing and release recovery.
- External-host testing and 60-minute Windows 32-track soak.

No milestone is marked complete solely because source was added. Do not publish this preview as the completed Windows replacement. NativeStudio/README.md documents the supported preview workflow and limitations. The validation report accompanying the deliverable records checks actually run.
