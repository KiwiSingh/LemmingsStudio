# LemmingsStudio buildfix255 — visionOS Splice MCP import parity seam

## Scope
Focused only on the visionOS build. macOS and Windows source paths are intentionally untouched.

## Added
- Expanded the visionOS Splice MCP window from discovery-only into a sample browser/import staging surface.
- Added MCP search tool-call preview data, including tempo/key-aware arguments and a safety note that keeps the app on official authenticated Splice MCP paths.
- Added staged Splice sample candidates so the UI, Arrangement insertion seam, and Step Sequencer mapping seam can be exercised before the real authenticated MCP download is wired.
- Added `importSampleCandidateToArrangement` for dropping/fetching a sample candidate into an audio track at the snapped playhead.
- Added `importSampleCandidateToStepSequencer` for mapping a candidate to a sequencer layer.
- Added a `Fetch on Drop` setting and placeholder fetch status path for the eventual authenticated download.
- Added a dedicated visionOS parity roadmap window and top-bar button.

## Guardrails
- No scraping.
- No auth bypass.
- No direct CDN guessing.
- Current sample URIs are explicit placeholders until official MCP download/tool calls are connected.

## Next steps for full macOS parity
1. Replace staged sample candidates with real authenticated Splice MCP search/download/preview tool calls.
2. Persist downloaded samples into the visionOS project package and rewrite clips/layers to project-relative file paths.
3. Add drag/drop from Splice MCP results into Arrangement lanes and Step Sequencer layers.
4. Bring device-rack parity forward: multi-slot AUv3 chains plus desktop bridge chains per track.
5. Finish mixer parity: richer meters, return automation, sidechain/send controls, and bus routing UI.
6. Add export/bounce parity for master, stems, selected clips, and Splice-derived assets.
7. Wire the Agentic MLX Lab into real local model management, screenshot capture, project context retrieval, and guarded tool execution.
