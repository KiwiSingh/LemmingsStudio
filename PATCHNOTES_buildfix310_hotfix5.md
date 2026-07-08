# buildfix310 hotfix 5

Release-blocking Xcode project-generation fix:

- Excludes `LemmingsStudioVision/Resources/Info.plist` from the Copy Bundle Resources phase.
- Keeps `LemmingsStudioVision/Resources/Assets.xcassets` in the resources phase so the visionOS AppIcon asset stack is still compiled by `actool`.
- Preserves `INFOPLIST_FILE = LemmingsStudioVision/Resources/Info.plist` so Xcode processes the target Info.plist exactly once.
- Carries forward hotfix 4's audio graph bus-routing fix and compiled-icon verification phase unchanged.

Root cause fixed: Xcode reported `Multiple commands produce .../LemmingsStudio.app/Info.plist` because the same plist was both processed as the target plist and copied as a bundle resource.
