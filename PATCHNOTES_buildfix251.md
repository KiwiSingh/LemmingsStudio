# LemmingsStudio buildfix251 — visionOS Spatial Mixer

## Added

- Persistent visionOS mixer state compatible with the Windows project schema:
  - per-track volume/pan/mute/solo
  - Return A/B sends
  - output routing to Master, Return A, or Return B
  - Return A/B state
  - master volume and mute
- Real AVAudioEngine track mixer nodes for scheduled project audio.
- Dedicated post-fader send-gain nodes for Return A and Return B.
- Return A delay and Return B reverb chains.
- Track, return, and master metering taps with peak/RMS snapshots.
- Precision Spatial Mixer window with faders, pan, sends, output routing, M/S, returns, master, and bridge-return strip.
- Volumetric Spatial Mixer overview window for Vision Pro.
- Desktop Bridge return level control in the Mixer.
- Liquid Glass-aware mixer surfaces using the existing visionOS skin system.
- README visionOS status update.

## Notes

- Project audio clips are routed through per-track mixer nodes.
- Post-fader sends use independent gain nodes rather than full-level fan-out.
- The current stock synth and hosted AU instrument paths still feed the shared synth bus; full per-track instrument-bus isolation is a later parity task.
- The Desktop Bridge audio return remains on its dedicated return engine in this pass, but is exposed as a controllable Mixer strip.
- Runtime validation still requires Xcode + visionOS SDK and real/simulator testing.
