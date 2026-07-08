# LemmingsStudio buildfix254

## visionOS startup branding

- Added the MagmaVance pre-splash video to the visionOS target resources.
- Added the LemmingsStudio splash image to the visionOS target resources.
- Added `VisionStartupBrandingView`, an immersive SwiftUI/AVKit startup sequence that plays the MagmaVance pre-splash first and crossfades into the LemmingsStudio splash before revealing the main editor.
- Added a **Replay Startup Branding** command under the skin/theme menu for quick validation while developing on simulator or device.
- Kept this visionOS-specific; macOS and Windows buildfix252/buildfix253 code paths are untouched.

## visionOS Splice MCP parity seam

- Added `VisionSpliceMCPClient`, `VisionSpliceMCPStatus`, and `VisionSpliceMCPTool`.
- Added a new **Splice MCP** window in the visionOS app.
- The client targets Splice's official streamable HTTP MCP endpoint, keeps the returned MCP session id, and discovers tools with `tools/list`.
- This pass does not scrape Splice, bypass auth, or expose hidden download behavior. It prepares the safe official-MCP insertion point for the next parity passes:
  - Splice search/results browser on visionOS
  - authenticated preview cards
  - Fetch-on-Drop to Arrangement
  - sample assignment into Step Sequencer lanes
  - account/credit status surfaced through official MCP tools when available

## Files added

- `Ports/visionOS/LemmingsStudioVision/Views/VisionStartupBrandingView.swift`
- `Ports/visionOS/LemmingsStudioVision/Views/VisionSpliceMCPView.swift`
- `Ports/visionOS/LemmingsStudioVision/Agentic/VisionSpliceMCP.swift`
- `Ports/visionOS/LemmingsStudioVision/Resources/LemmingsSplash.png`
- `Ports/visionOS/LemmingsStudioVision/Resources/MagmaVancePreSplash.mp4`
- `Ports/visionOS/LemmingsStudioVision/Resources/MagmaVancePreSplash_60.mp4`

## Files changed

- `Ports/visionOS/LemmingsStudioVision/App/LemmingsStudioVisionApp.swift`
- `Ports/visionOS/LemmingsStudioVision/App/VisionStudioModel.swift`
- `Ports/visionOS/LemmingsStudioVision/Views/VisionRootView.swift`
- `Ports/visionOS/README.md`

## Validation notes

- The visionOS XcodeGen project already includes `LemmingsStudioVision` recursively as its source root, so the added Swift and resource files are picked up by the target without touching macOS or Windows project files.
- The splash falls back gracefully if either media asset is missing.
- Real Splice MCP auth/tool discovery depends on Splice accepting native clients at the official remote MCP endpoint.
