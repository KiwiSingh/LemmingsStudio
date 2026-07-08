# LemmingsStudio buildfix246 — visionOS foundation

## Added

- `Ports/visionOS/` native SwiftUI visionOS application target scaffold.
- `.lemmings` project UTI/document association.
- Security-scoped project import.
- Lightweight visionOS-compatible decoder for the existing project JSON schema.
- Transport: play, pause, stop, seek, beat tracking.
- Basic Arrangement View: track headers, ruler, beat/bar grid, MIDI/audio clips, playhead, selection.
- Desktop Plug-in Bridge protocol model for future AU/VST3 hosting on Mac/Windows.
- Reserved `experimentalWine` compatibility-provider seam, kept outside the visionOS execution model.
- XcodeGen project definition and `build-visionos.sh` helper.
- visionOS build and architecture README.

## Intentional limits

This foundation does not yet render full project audio or host AUv3 plug-ins. Those are subsequent parity passes. The transport is currently a timeline clock used to exercise UI/project compatibility.
