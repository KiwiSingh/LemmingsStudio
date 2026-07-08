# buildfix305 hotfix 3

Fixes the Xcode 27 / SwiftUI compile failure in `VisionArrangementAutomationDock.swift` where `.fill(.accent)` was not a valid `ShapeStyle` member.

Changed to:

```swift
.fill(Color.accentColor)
```

This archive also retains hotfix 1 (AVAudioPlayerNode `scheduleBuffer` overload disambiguation) and hotfix 2 (Swift 6 actor-isolated `deinit` cleanup), plus the corrected buildfix305 visionOS feature work and minimal model-bundle default.
