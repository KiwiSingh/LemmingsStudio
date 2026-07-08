# buildfix277 — visionOS first source compile pass

Public versions remain macOS v2.0, Windows v2.0, visionOS v1.0.

Fixes surfaced by the first full Xcode visionOS source compile:
- removed obsolete duplicate `VisionStudioModel.companionParity` extension accessor; the model now has one observable stored state only;
- replaced `glassEffect(_:in:)`, explicitly unavailable on visionOS, with native `glassBackgroundEffect`;
- snapshot `VisionCompatibilityLabState` before entering detached Wine ARM64 probe work to respect MainActor isolation;
- made floating MIDI-key border styles explicit `Color` values for Swift 6 type inference;
- rewired the Agentic MLX panel from stale prototype methods to the real runtime path: `runLocalMLXAgent()` and `executeConfirmedMLXToolPlan()`;
- preserves buildfix276 generic simulator destination and scoped package-plugin/macro validation flags.
