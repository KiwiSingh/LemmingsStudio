# LemmingsStudio buildfix310 hotfix 4

Release-blocker fixes:

- Fixed AVAudioEngine graph abort when starting MIDI recording with per-track FX active.
- Track sends and direct outputs now use deterministic, non-colliding mixer input buses.
- Preserved per-track FX insert routing and track-qualified automation.
- Explicitly classifies visionOS Resources as a resource build phase in XcodeGen.
- Restored correct CFBundleIcons dictionary structure with CFBundleIconName = AppIcon.
- Normalized AppIcon image-stack metadata authorship to the app bundle identifier.
- Added an Xcode post-build gate that fails if the built app lacks Assets.car or primary AppIcon metadata.

The crash log pointed to VisionAudioEngine.scheduleProjectAudio at the AVAudioEngine multi-output connection. The previous routing reused bus 0 for multiple track/send inputs, producing an invalid graph that AVFAudio terminated with SIGABRT during graph preparation.
