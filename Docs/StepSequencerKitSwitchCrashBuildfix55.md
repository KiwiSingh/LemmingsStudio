# Step Sequencer Kit Switch Crash Buildfix 55

This buildfix protects Step Sequencer kit/groove switching from render-thread races.

## Problem

Creating a new Sequencer track and immediately switching to a preset kit such as Slap House could crash because the UI was replacing the track kind, sequencer layers, plugin target, and generated clips while the AVAudioSourceNode render callback could still be reading the previous track/lane arrays.

## Fix

- Added `AudioEngine.isRunning` so app-level mutation code can pause CoreAudio briefly.
- Added an AppState step-sequencer mutation guard that stops the audio engine, mutates the kit/lane state, rebuilds, and restarts audio if it was previously running.
- Wrapped drum kit, drum groove, and Bhangra groove changes in the guarded mutation path.
- Made New Sequencer track creation normalize the track into a safe Tech House drum-sequencer baseline:
  - clears stale plugin targets
  - removes stale instrument slots
  - removes arp devices from the default kit
  - clears generated clips
  - syncs lane cells after loading the groove
  - resets step render state before rebuilding

This is intended to stop crashes from New Sequencer -> Slap House / EDM / Tech House and similar kit switches.
