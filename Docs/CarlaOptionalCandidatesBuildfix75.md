# Carla Optional Candidates Buildfix 75

Fixes a Swift/Xcode beta compile failure in `CarlaBridgeSupport.swift` where optional bundled/cached Carla executable URLs were mixed into `[URL]` arrays without being unwrapped.

## Changes

- `installedCarlaExecutableCandidates` now compacts optional bundled/cached Carla executable URLs before returning `[URL]`.
- `installedCarlaSingleExecutableCandidates` does the same for `carla-single`.
- Keeps Homebrew formula paths and app-bundled helper paths intact.

This is a compile-only fix; it does not change the runtime Carla single-plugin bridge behavior.
