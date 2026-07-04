# Buildfix 227 — Windows parity reset pass

This pass treats the macOS app as the reference implementation and stops presenting the Windows tree as complete when it is not.

## Added in this pass

- Windows startup sound now uses the same branded `LemmingsStartup.wav` resource as macOS.
- Windows startup splash plays the startup sting asynchronously and never blocks launch if audio fails.
- Added a Windows Session / Clip Launcher workspace so the Windows shell is not Arrangement-only.
- Added a proper lower Clip/Track Inspector deck instead of a raw `PropertyGrid`.
- Inspector now exposes clip gain, pitch semitones/cents, warp enable, clip BPM, start beat, length, track volume, pan, mute, solo, and arm.
- Added transport-level metronome toggle.
- Windows render/export now prints the metronome into playback/export when enabled, so timing follows the same offline render clock instead of a UI timer.
- Browser now starts with stock instruments, stock effects, and agentic tool categories before a user library scan.
- Existing buildfix226 Step Sequencer and Piano Roll remain wired into project state and playback/export.

## Still not full parity yet

These are intentionally documented rather than hidden:

- Native Windows VST3 hosting and plugin editor windows are not implemented yet.
- Live Windows MIDI hardware input/learn is not implemented yet.
- Recording/audio input is not implemented yet.
- Clip warping is still a lightweight render stretch, not the macOS-quality warp path.
- Splice integration is still a port-layer workflow, not identical to the macOS implementation.
- AI chatbot/model selection still needs the final text-model decision.
- RVC dependency/model packaging remains separate from the stable Windows beta path.

## Recommended next parity order

1. Replace remaining placeholder copy and visual mismatch with Mac-like panels.
2. Port recording/input monitoring.
3. Port live MIDI input/MIDI learn.
4. Implement VST3 scanning + hosting + editor windows.
5. Harden Splice workflow parity.
6. Improve warp/time-stretch quality.
7. Bring agentic feature UX closer to macOS.
