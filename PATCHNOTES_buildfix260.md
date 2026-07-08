# LemmingsStudio buildfix260 — Semantic Project Graph Foundation

Buildfix260 starts the AI-native architecture inspired by `theDAW`, but keeps it native-Swift and platform-aligned instead of moving LemmingsStudio toward a browser/FastAPI stack.

## Added

- **visionOS Semantic Project Graph**
  - New `LemmingsStudioVision/Semantic/` module.
  - Tracks, MIDI clips, audio clips, mixer paths, return buses, master bus, AUv3 state, spatial objects, step sequencer lanes, and Compatibility Lab candidates are converted into stable semantic nodes and edges.
  - The graph is metadata-only: it does not execute DSP, load plugins, or mutate the project.

- **Semantic Graph window on visionOS**
  - New top-bar entry: `Semantic Graph`.
  - New window id: `semantic-graph`.
  - Shows node/edge metrics, filters by node kind, relationship preview, and AI context preview.

- **Project save/open integration**
  - The visionOS project now stores an optional `semanticGraph` snapshot.
  - Graph is rebuilt for new projects, lazily generated for older projects, and refreshed before save.

- **macOS semantic graph seam**
  - New `Sources/LemmingsStudio/Semantic/SemanticProjectGraph.swift`.
  - Builds the same style of metadata graph from `ProjectDocument`.
  - Adds an `agentContext(from:)` helper for future MLX agents, project memory, Host Mode telemetry, and parity audits.

## Why this matters

This gives LemmingsStudio a shared vocabulary across macOS and visionOS:

- tracks become semantic nodes, not just array indices;
- clips gain stable keys for AI edits and memory;
- routing becomes graph edges;
- plug-in/compatibility backends become inspectable metadata;
- spatial objects can be linked back into the musical project;
- future MLX agents can consume compact context instead of raw UI state.

## Safety / stability

- No Wine/FEX runtime execution added in this buildfix.
- No plugin binary loading added in this buildfix.
- No audio-engine behavior changed.
- macOS and Windows runtime paths remain untouched except for the new metadata-only macOS semantic graph source file.

## Next full macOS parity steps

1. **buildfix261 — MLX Runtime Core**
   - Local model manager.
   - Quantized model registry.
   - Agent scheduler.
   - Semantic graph context injection.
   - Vision-language screenshot/context handoff.

2. **buildfix262 — Living Project Memory**
   - Per-project SQLite memory store.
   - Attach memory events to semantic node stableKeys.
   - Store accepted/rejected AI edits.
   - Restore project intent months later.

3. **buildfix263 — Integrated Host Mode Live Endpoints**
   - macOS LemmingsStudio exposes Companion Host Mode directly.
   - visionOS discovers it over Bonjour.
   - Stream plugin editor surfaces and route gestures back to the Mac.

4. **buildfix264 — Mixer + Bounce Parity**
   - Real return/send/master routing parity.
   - Mac-rendered bounce/stem/export request path.
   - Export telemetry reflected in the semantic graph.

5. **buildfix265 — Wine ARM64 Smoke Test**
   - First sideload-only Windows ARM64 VST shell probe.
   - Keep FEX/x64 behind Gojira dry-run gates until ARM64 Wine has a baseline.

