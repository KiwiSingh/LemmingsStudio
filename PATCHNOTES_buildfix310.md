# LemmingsStudio buildfix310 — First User-Facing visionOS Release Candidate

## Stock FX + universal spatial automation

- Added a native Stock FX Rack workspace.
- Added LemmingsFilter with logarithmic cutoff and resonance control.
- Added LemmingCrusher with crush intensity and wet/dry mix.
- Added BurrowDelay with time, feedback, and wet/dry mix.
- Added LemmingVerb wet control.
- Added LemmingDrive with drive and wet/dry mix.
- Added a shared stock-FX parameter registry so FX are exposed through the same automation address model as project tempo, mixer, spatial coordinates, and Companion plug-in parameters.
- Added Stock FX Parameters to Automation's expose menu.
- Spatial Stage mappings can target stock FX parameters with per-lane min/max range and inversion.
- Gesture performances continue to record into ordinary editable VisionAutomationLane breakpoint data.
- Added Stock FX Rack to the Workspaces menu.

## Release infrastructure preserved from bf309

- Proper non-empty layered visionOS AppIcon stack.
- XcodeGen project generation and `open-in-xcode.sh` workflow.
- Xcode post-build minimal-model staging.
- Minimal model profile remains the default.
- Simulator package and unsigned/resignable IPA packaging remain available.
