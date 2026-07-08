# LemmingsStudio buildfix271 — Launch Parity Matrix

Legend: **Implemented in source** means the relevant production path exists in this bundle. **Hardware validation required** means source inspection alone cannot certify timing, latency, signing, thermals, permissions, or third-party service behavior.

| Capability | macOS v2.0 | Windows v2.0 | visionOS v1.0 | Launch note |
|---|---|---|---|---|
| Arrangement / clip editing | Implemented | Implemented | Implemented | Validate project round-trip and long-session editing |
| Piano Roll | Implemented | Implemented | Implemented | Validate MIDI timing and selection ergonomics |
| Step Sequencer | Implemented | Implemented | Implemented | visionOS includes Splice lane mapping path |
| Mixer | Implemented | Implemented | Implemented | Validate automation interaction and return behavior |
| Audio recording | Implemented | Implemented | Implemented | visionOS punch/count-in/pre-roll and comping require device test |
| Take folders / comping | Platform-native workflow | Recording workflow | Implemented | visionOS region comp consolidation requires stress test |
| Automation | Implemented | Implemented | Implemented | visionOS Read/Write/Touch/Latch and spatial automation need hardware validation |
| Native plugin hosting | AU | VST3 | AUv3 / platform-supported AU path | Third-party plugin matrix still required |
| Integrated Mac Host Mode | Host server | N/A | Bridge client | Validate discovery, reconnect, streamed editor input, and latency |
| Streamed plugin editor | Host capture/input path | N/A | Spatial surface client | Validate JUCE/Cocoa/generic AU editors |
| Project-level remote bounce | Host renderer | Local export path | Manifest client | Validate master, selected track, stems, returns, hosted plugin return |
| Local AI chat | Ollama | Ollama | MLX runtime | visionOS requires real model download/inference profiling |
| Semantic Project Graph | Implemented | Platform roadmap parity | Implemented | Agent context path present on visionOS |
| Living Project Memory | Implemented path | Platform roadmap parity | Implemented | Validate project persistence and memory growth |
| Splice MCP | Desktop workflows | Desktop workflows | Search/preview/download/import/mapping path | Authenticated beta workflow must be tested live |
| Bluetooth/CoreMIDI | CoreMIDI | Windows MIDI | CoreMIDI/Bluetooth MIDI path | Test LUMI/ROLI-class devices on hardware |
| Spatial editing | N/A | N/A | Implemented | Validate scene persistence and gesture recording |
| Wine ARM64 research | N/A | Native Windows | Bring-up pipeline | Experimental; runtime binaries not bundled |
| Simulator distribution | N/A | N/A | Packaging script | Clean-machine Simulator launch required |
| Hardware distribution | Signed/notarized as chosen | Installer | Resignable IPA packaging pipeline | End-user signing/re-signing and device installation required |

## Release blockers vs. experiments

Do not block the public macOS/Windows builds on Wine ARM64 research. The Wine lane is explicitly experimental.

For visionOS, the release blockers are:

1. Xcode compile and package success.
2. Simulator ZIP launch on a clean environment.
3. End-user sign/re-sign flow, IPA install, and first launch on Apple Vision Pro.
4. Project save/open round-trip.
5. Recording permission and recording stability.
6. Automation playback and write modes.
7. Host Mode discovery/reconnect and at least one tested AU editor surface.
8. Splice authenticated search/preview/download/import, when shipping that integration enabled.
9. MLX load/inference/cancel/unload on at least one supported model configuration, when shipping local agents enabled by default.

## Experimental badges required on the website

The following must remain clearly labeled **Experimental** in public copy:

- Wine ARM64 on visionOS
- FEX/x86-64 translation research
- universal desktop-plugin compatibility claims
- Windows VST3 execution on visionOS
- arbitrary Windows plugin-editor surface bridging

