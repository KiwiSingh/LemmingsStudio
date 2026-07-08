# Buildfix253 — Spatial Editing + Local MLX Agentic Foundation

## Baseline

This patch is based directly on `LemmingsStudio_buildfix252_visionos_piano_roll_step_sequencer(3).zip`.

## Spatial editing

- Added a persistent visionOS spatial scene graph via `VisionSpatialScene`.
- Added `VisionSpatialObject` entries for Arrangement, Mixer, Plug-in Rack, and Agent Panel surfaces.
- Added transform persistence for position, rotation, and scale using Codable-safe vector structs.
- Added a dedicated **Spatial Editor** window.
- Added selectable spatial surfaces with visibility toggles.
- Added transform sliders for X/Y/Z position, pitch/yaw/roll rotation, and X/Y/Z scale.
- Added nudge, snap, reset, duplicate, delete, undo, and redo actions.
- Added scene defaults that place mixer and plug-in rack surfaces to the sides of the Arrangement surface.
- Kept the experimental volumetric Spatial Control Deck intact.

## Agentic MLX foundation

- Added `VisionMLXAgentBridge` as a local-first model/tool-call seam.
- Added model presets for common quantized multimodal MLX target families.
- Added a dedicated **Agentic MLX Lab** window.
- Added project-context extraction for project name, tempo, key, selected clip, track count, and spatial object count.
- Added safe offline tool-plan generation so the UI can be tested before wiring a real MLX runtime.
- Added explicit confirmation semantics: the model proposes tool calls; LemmingsStudio applies only approved safe actions.

## UI integration

- Added **Spatial Editor** and **AI Agent** buttons to the main visionOS toolbar.
- Added `WindowGroup` scenes for both new panels.
- Updated project model persistence without breaking old project decoding by making the new scene optional.

## Files added

- `Ports/visionOS/LemmingsStudioVision/Spatial/VisionSpatialEditing.swift`
- `Ports/visionOS/LemmingsStudioVision/Spatial/VisionStudioModel+SpatialEditing.swift`
- `Ports/visionOS/LemmingsStudioVision/Spatial/VisionSpatialEditorView.swift`
- `Ports/visionOS/LemmingsStudioVision/Agentic/VisionMLXAgentBridge.swift`
- `Ports/visionOS/LemmingsStudioVision/Agentic/VisionAgentPanelView.swift`

## Files changed

- `Ports/visionOS/LemmingsStudioVision/App/VisionStudioModel.swift`
- `Ports/visionOS/LemmingsStudioVision/App/LemmingsStudioVisionApp.swift`
- `Ports/visionOS/LemmingsStudioVision/Models/LemmingsProject.swift`
- `Ports/visionOS/LemmingsStudioVision/Views/VisionRootView.swift`
- `Ports/visionOS/README.md`
- `README.md`

## Validation performed here

- ZIP extraction and repackaging from the provided buildfix252 source archive.
- Basic Swift delimiter balance checks on the visionOS target.
- Verified new source files are included by the existing XcodeGen source-folder rule.
- Verified ZIP integrity after packaging.

Actual Xcode/visionOS SDK compilation still requires a Mac with Xcode and the visionOS SDK installed.
