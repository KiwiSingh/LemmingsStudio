# LemmingsStudio buildfix290

## visionOS audio real-time isolation hotfix

- Fixes the Step Sequencer/transport playback crash that still occurred in buildfix289.
- Moves `VisionVoiceBank` out of the `@MainActor VisionAudioEngine` type so AVAudioSourceNode's real-time callback no longer calls actor-isolated nested state.
- Moves `VisionMeterBox` out of the actor-isolated engine type for the same reason, preventing the same class of Swift executor trap in AVAudio tap callbacks.
- Keeps the buildfix289 Step Sequencer transport controls and visionOS icon asset work.

The crash signature addressed is `_swift_task_checkIsolatedSwift` on `AURemoteIO::IOThread` while executing the VisionAudioEngine source-node render callback.
