# LemmingsStudio buildfix276

## visionOS MLX macro validation hotfix

- Keeps the buildfix275 scoped `-skipPackagePluginValidation` workaround for MLX Swift's transitive `CudaBuild` package plugin.
- Adds scoped `-skipMacroValidation` to scripted visionOS xcodebuild invocations so `MLXHuggingFaceMacros` can be used in headless/scripted builds without requiring an interactive trust prompt.
- Adds `VISION_SKIP_MACRO_VALIDATION=0` as an opt-out for developers who prefer normal Xcode macro trust validation.
- Simulator builds continue to default to `generic/platform=visionOS Simulator`.
- Public app versions remain macOS v2.0, Windows v2.0, and visionOS v1.0.
