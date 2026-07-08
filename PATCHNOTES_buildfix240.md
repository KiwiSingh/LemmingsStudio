# LemmingsStudio buildfix240 — Windows Splice/sample workflow parity

## Scope
Windows local-first sample workflow and Splice integration parity pass.

## Implemented
- Reworked the Windows Splice panel into a local-first browser with separate **Splice Search** and **Local Cache** tabs.
- Added local cache refresh and cache-folder access.
- Added sample audition/stop controls using NAudio.
- Added explicit **Fetch on Drop** behavior for remote Splice results.
- Cached Splice files can be dragged directly as ordinary file drops without another network request.
- Remote search results can be dragged as a LemmingsStudio Splice payload; Arrangement and Step Sequencer resolve/download only when the drop is accepted.
- Added graceful no-op failure behavior: a failed fetch logs the error and does not create a broken clip/lane.
- Added drag/drop into Arrangement at the drop beat and existing audio-track target where applicable.
- Added drag/drop into Step Sequencer lanes.
- Added **Send to Sequencer** and **Add to Arrangement** actions.
- Added BPM/key/type metadata propagation from Splice search results.
- Added loop-aware tempo-fit/warp flagging and natural beat-length derivation from duration + source BPM.
- Added filename BPM inference for locally cached samples where possible.
- Added a reusable `SpliceDropBroker` so download/cache logic is shared by multiple drop targets.
- Fixed the Windows audio engine so `SequencerLayer.SourcePath` sample files are actually rendered per hit, including per-layer volume and pan. Unsampled lanes continue through stock MIDI/drum synthesis.

## Notes
- The first download of a Splice asset may still spend a Splice credit according to the upstream service behavior. Cache reuse avoids redundant downloads.
- Splice MCP availability/authentication remain external-service dependencies; local cached samples remain usable when Splice is unavailable.
- Tempo-fit uses the existing Windows clip warp path and is not a high-quality phase-vocoder stretch implementation.

## Validation
This source patch was structurally inspected in the Linux container. The Windows .NET/Visual Studio toolchain is not installed here, so compile and runtime validation remain required on the Windows VM.
