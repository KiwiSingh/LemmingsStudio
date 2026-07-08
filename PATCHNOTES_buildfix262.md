# LemmingsStudio buildfix262 — Living Project Memory

buildfix262 follows the agreed roadmap after buildfix260 Semantic Project Graph and buildfix261 MLX Runtime Core. This patch adds the first durable **Living Project Memory** layer to the visionOS build, so future MLX agents can reason from actual project history instead of only the current project graph.

## Added

- New visionOS **Living Project Memory** window.
- Project-local memory model for:
  - session snapshots,
  - mix decisions,
  - arrangement decisions,
  - plugin decisions,
  - recording decisions,
  - export notes,
  - rejected ideas,
  - learned preferences,
  - unresolved issues,
  - AI notes.
- Memory context digest for MLX agents.
- Memory nodes inside the Semantic Project Graph.
- Learned preference extraction from Preference memory events.
- Pinned memories and unresolved issue tracking.
- Session snapshot capture for tempo, track count, and semantic node count.
- Memory compaction pass that summarizes preferences, pinned decisions, exports, and open issues.
- Save/open/new-project hooks to initialize and update project memory.
- Root toolbar entry for the Memory window.
- Status bar memory event counter.
- MLX Runtime dry-run now includes memory event/preference counts.

## Why this matters

This turns LemmingsStudio projects into persistent creative sessions. The AI layer can now know things like:

- what the user already tried,
- what they rejected,
- what mix decisions were made,
- what preferences were learned,
- what problems are still unresolved,
- what exports or session milestones happened.

That is the foundation for “continue where I left off” workflows.

## Current safety model

- Memory is project-local, not global.
- Memory is JSON-serializable inside the project model for this build.
- MLX context inclusion is user-toggleable.
- Semantic graph inclusion is user-toggleable.
- Learned preferences are explicit: add a Preference memory event to seed them.

## Notes

This is the first pass. A future build can swap the backend to a `Project.sqlite` sidecar while preserving the same Swift value types and UI contracts.

## Next steps for full macOS parity

1. Bring Living Project Memory to the macOS project document model.
2. Wire memory into real MLX agent prompts and tool-call previews.
3. Add integrated macOS Host Mode live endpoints.
4. Finish streamed plugin editor input from visionOS to macOS.
5. Add real bounce/stem export parity.
6. Add recording/take-folder parity.
7. Run the first Wine ARM64 smoke test behind Compatibility Lab.
