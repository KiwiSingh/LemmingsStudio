# LemmingsStudio buildfix289

## visionOS icon, Step Sequencer transport, and render-thread isolation hotfix

- Replaced the nonfunctional `AppIcon.solidimagestack` with a conventional three-layer `AppIcon.imagestack` using embedded image sets.
- Added Stop and Play/Pause transport controls directly to the Step Sequencer header.
- Moved `AVAudioSourceNode` callback construction into a `nonisolated` factory so Swift 6 does not enforce MainActor executor isolation on the AURemoteIO render thread.
- Removed per-buffer scratch allocation on mono render paths by adding direct mono rendering in `VoiceBank`.
