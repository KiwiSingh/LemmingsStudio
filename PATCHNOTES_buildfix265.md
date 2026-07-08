# LemmingsStudio buildfix265 — visionOS Splice MCP workflow

Public versions remain unchanged:

- macOS v2.0
- Windows v2.0
- visionOS v1.0

## Scope

This buildfix is the launch-parity Splice MCP pass for visionOS.

## Added

### Official authenticated MCP workflow

- Uses the official Streamable HTTP endpoint at `https://mcp.splice.com/mcp`.
- Keeps MCP session IDs returned by the server.
- Dynamically discovers tools and their input property names.
- Never scrapes Splice pages, copies tokens from other MCP clients, or hard-codes private CDN endpoints.
- Detects authentication-required HTTP responses and sends the user through the official Splice browser flow before reconnecting.

### Real sample search

- Replaces demo candidates with live `tools/call` search requests.
- Picks the best advertised search tool dynamically.
- Maps query, BPM, key, scale, and limit only when the advertised input schema supports those names.
- Parses nested JSON and JSON embedded in MCP text content into sample candidates.
- Preserves title, creator, BPM, key, tags, preview URL, download URL, page URL, and asset/sample ID when available.

### Preview

- Downloads an advertised preview audio URL to a temporary preview cache.
- Auditions it through the visionOS audio engine.

### Licensed download/import

- Picks the best advertised download/save tool dynamically.
- Uses the official MCP tool call and current MCP session.
- Accepts a returned local file path or downloadable audio URL.
- Persists downloaded audio under the current project’s sibling asset directory:
  `<Project>.lemmings-assets/Samples/Splice/`
- Writes a `.splice.json` metadata sidecar beside the downloaded audio.
- Adds a Living Project Memory event after a successful import.

### Arrangement integration

- Download + Arrangement inserts the downloaded project-local sample.
- Splice result rows are draggable.
- Arrangement track lanes accept Splice result drops.
- With Fetch on Drop enabled, drop triggers authenticated MCP download first, then insertion.
- With Fetch on Drop disabled, only already-downloaded project-local Splice samples are inserted.

### Step Sequencer integration

- Download + Sequencer maps the downloaded sample to a sequencer layer.
- Sequencer layer rows accept Splice result drops.
- Fetch on Drop behavior matches Arrangement View.

### Auto-stretch hook promoted to playback behavior

- Splice sample BPM and key are persisted on Arrangement audio clips.
- Imported clips can opt into auto-stretch.
- The visionOS audio engine uses an `AVAudioUnitVarispeed` node for BPM-rate adaptation when source BPM differs from project BPM.
- The playback-rate calculation uses `projectBPM / sourceBPM`.

## Validation performed

- Swift parser validation passed for the modified Splice MCP client, MCP browser UI, Arrangement View, Step Sequencer View, project models, studio model, and audio engine.
- Public version metadata was left unchanged.

## Next parity work, in the requested order

1. Full project-level Host Mode bounce: master, selected tracks, stems, returns, and hosted plug-in returns.
2. Recording parity: punch in/out, count-in, pre-roll, take lanes, region slicing, swipe comping.
3. Automation parity: persisted automation, Write/Touch/Latch, curve handles, spatial gesture recording.
4. MLX real model loading and constrained tool execution on hardware.
5. Wine ARM64 bring-up and first successful VST host probe.
6. Final visionOS/macOS feature-parity audit and launch hardening.
