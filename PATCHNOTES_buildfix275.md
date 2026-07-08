# buildfix275 — visionOS MLX Package Plugin Validation Hotfix

- Changes the default simulator destination to `generic/platform=visionOS Simulator`.
- Adds scripted `-skipPackagePluginValidation` handling for the pinned MLX Swift dependency graph.
- Applies the flag consistently to simulator, device, archive, Simulator ZIP, and resignable IPA build paths.
- Allows opting back into normal plugin validation with `VISION_SKIP_PACKAGE_PLUGIN_VALIDATION=0`.
- Public versions unchanged: macOS v2.0, Windows v2.0, visionOS v1.0.
