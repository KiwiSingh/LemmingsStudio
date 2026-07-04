# Buildfix 200 — Automation Lanes Drive Live DSP

## Problem
Automation breakpoints could be drawn, but device parameters did not actually change during playback/render.

Manual rack changes worked because Buildfix 193 synced `DeviceModel.params` into each live DSP node immediately before processing. However, automation was evaluated earlier in the block, and the later rack-param sync copied the static/manual knob value back over the DSP node. The result: lanes looked correct in the UI, but the processor heard the unautomated value.

Example: automating Bit Crusher `downsample` drew a visible lane, but playback kept using the manually set downsample value.

## Fix
The audio engine now applies automation after static rack parameters are synced and before each device processes audio.

Order per block is now:

1. Copy manual/static rack values into the live DSP node.
2. Apply the automation lane value for this block's beat.
3. Process the device.

This preserves the user's saved/manual knob position while making automation audible.

## Scope
- Track device automation now drives live DSP.
- Stock devices such as Bit Crusher/Redux now respond to automated parameters.
- Device On/Off automation is applied at device-processing time.
- Group/bus device automation now uses the current playback beat instead of always reading beat 0.

## Files changed
- `Sources/LemmingsStudio/Audio/AudioEngine.swift`
