# Buildfix88 — Sound Agent uses the live AU instance

This build fixes the Serum 2 false-success path where the Sound Agent reported that a conservative patch was applied while the visible Serum 2 window stayed on `- Init -`.

## Root cause

Earlier builds opened the plug-in editor by instantiating a separate `AVAudioUnit` for the window. The audio engine created its own `HostedAUInstrument` instance for playback/automation, so the Sound Agent could apply values to one AU while the user was looking at another freshly initialized AU.

That also made Serum 2 show `DAW suspended processing` more often because the visible editor instance was not the source node the engine was rendering.

## Fix

- `HostedAUInstrument` now exposes its live `AUAudioUnit`.
- The plug-in editor attaches to that exact live AU when the selected track hosts the target.
- The Sound Agent starts the engine after inserting the AU so CoreAudio keeps pulling silence and the synth is not left in a suspended-processing state.
- AU parameter writes use `setValue(_:originator:)` as well as `value` assignment.
- If zero AU parameters are actually written, the target now throws instead of reporting a fake success. The error includes a small list of exposed AU parameters to help improve mapping.

## Scope

No Splice MCP/download/preview files were changed.
