# buildfix305 — corrected visionOS spatial automation integration

This corrected source tree fixes the incomplete first bf305 package and integrates the requested visionOS workflow into the main DAW surface.

## User-facing changes
- Arrangement View now contains a persistent Automation dock with project tempo, mixer, and spatial exposure actions, lane selection, arm/write-mode controls, breakpoint graph editing, and direct access to the Spatial Automation Stage and full lane editor.
- Project Tempo is a first-class automation target and participates in the same lane evaluator as other automation.
- MIDI clips now expose a direct Record/Stop control that records into the chosen clip.
- The floating MIDI keyboard is now hosted in a volumetric visionOS window and includes a direct MIDI Record/Stop control.
- The top transport area now has editable BPM controls, project key/scale selection, and a Circle of Fifths launcher.
- Added a native visionOS Circle of Fifths window synchronized with project key, scale assist, and piano-roll scale logic.
- Spatial Automation Stage remains mapped into ordinary breakpoint automation lanes for exact cleanup and deterministic export.

## Build workflow correction
- `VISION_MODEL_BUNDLE_PROFILE` now defaults to `minimal` in build, model-preparation, and release scripts. `full` remains explicit opt-in.
- Source root is packaged as `bf305_work/`.
