# LemmingsStudio buildfix310 hotfix 6

Release-blocking visionOS AppIcon metadata correction.

## Changes

- Corrected the visionOS `CFBundleIcons` structure in `project.yml` so `CFBundlePrimaryIcon` is the string `AppIcon`.
- Corrected the checked-in `Info.plist` to use the same visionOS-specific string form.
- Updated `Scripts/verify-built-icon.sh` to validate `:CFBundleIcons:CFBundlePrimaryIcon` directly.
- No Swift, audio, MIDI, FX-routing, automation, project-model, or MLX model-staging code changed.

## Expected built plist shape

```text
CFBundleIcons
└── CFBundlePrimaryIcon = AppIcon
```
