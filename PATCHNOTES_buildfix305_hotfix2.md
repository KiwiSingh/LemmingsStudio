# buildfix305 hotfix 2

- Fixes Swift 6 / Xcode 27 actor-isolation compile failure in `VisionStudioModel` deinitialization.
- Changes the destructor to `isolated deinit` so the `@MainActor`-isolated `autosaveTask` can be cancelled safely during teardown.
- Retains hotfix 1's Xcode 27 AVAudioPlayerNode scheduleBuffer overload disambiguation.
- Keeps the minimal vision model bundle profile as the default.
