# buildfix305 — visionOS hybrid spatial automation

This build is visionOS-only and extends buildfix304. The macOS and Windows targets are not changed.

## Hybrid automation workflow
- Adds a dedicated **Spatial Automation Stage** for expressive performance input.
- Keeps the existing breakpoint automation lane model as the source of truth.
- Spatial performances write ordinary beat/value automation points, so recorded motion can be refined later with exact beat, value, curve type, and curve-handle editing.
- Live performance input and timeline playback share the same target-routing path for Mixer, Mac Companion parameters, and spatial surface parameters.
- Recorded data remains compatible with the automation evaluator used by the buildfix304 native export path.

## Expressive gesture mappings
Each automation lane can optionally map to one visionOS-only expressive gesture dimension:
- Sway — horizontal movement
- Pulse — vertical movement
- Glide — continuous depth/travel control
- Strike — transient intensity
- Press — sustained intensity
- Sculpt — broad shape/spread control

Mappings support:
- Per-lane normalized minimum and maximum range
- Inversion
- Many lanes mapped to the same gesture
- Live target control even when the lane is not recording
- Recording governed by the lane's existing Arm + Read/Write/Touch/Latch state

## Spatial Automation Stage UI
- Two-dimensional Sway × Pulse performance field.
- Continuous Glide, Press, and Sculpt controls.
- Soft, Medium, and Hard Strike triggers.
- Live beat/status display.
- Mapping monitor showing all lanes assigned to each gesture dimension.
- Explicit Release Latches control.

## Persistence and compatibility
- Adds optional spatial gesture mapping metadata to `VisionAutomationLane`.
- Decoding defaults preserve compatibility with projects saved before buildfix305.
- Unmapped lanes remain conventional automation lanes with unchanged behavior.

## Validation
- All visionOS Swift source files pass Swift parser validation under Swift 6.2.1 in the available build environment.
- Full `xcodebuild` validation could not be run in this Linux container because Xcode and the visionOS SDK are unavailable; run `Ports/visionOS/build-visionos.sh` on the Mac/Xcode environment for the platform compile.
