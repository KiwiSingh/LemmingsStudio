# LemmingsStudio buildfix286

## visionOS simulator launch/audio-route hardening

- Removed eager `VisionAudioEngine.start()` from `VisionStudioModel.init()` so the app can launch even when the visionOS simulator has not exposed a usable audio route yet.
- Audio now starts lazily when playback is requested. A missing/zero-channel route leaves the app alive and reports an `Audio unavailable` status instead of attempting an invalid graph start during app initialization.
- Removed forced 48 kHz stereo formats from the core AVAudioEngine graph and project mixer/send connections so AVAudioEngine can negotiate the simulator/device route format.
- Changed the synth `AVAudioSourceNode` to negotiate its format from downstream connections and safely render into mono or stereo buffer layouts.
- Added one-time graph configuration so a failed first start can be retried when an output route becomes available without duplicate node attachments or meter taps.
- Removed forced stereo formats from hosted effect reconnection paths.
- Added the 1024x1024 LemmingsStudio visionOS app icon source to the visionOS asset catalog as `AppIcon`.

## Public versions

- macOS: 2.0 (build 2.0.0)
- Windows: 2.0.0 (assembly/file 2.0.0.0)
- visionOS: 1.0 (build 1.0.0)
