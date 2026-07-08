# LemmingsStudio buildfix291

## visionOS app icon registration + meter callback actor isolation hotfix

- Adds `CFBundleIcons.CFBundlePrimaryIcon = AppIcon` to the checked-in visionOS Info.plist.
- Mirrors the same icon declaration in `Ports/visionOS/project.yml` so XcodeGen regeneration preserves it.
- Keeps `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` and the layered `AppIcon.imagestack` asset.
- Moves AVAudio meter tap callback construction to a `nonisolated` factory.
- Prevents Swift 6 executor assertions when AVFAudio invokes meter callbacks on `RealtimeMessenger.mServiceQueue`.
