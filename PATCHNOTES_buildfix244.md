# LemmingsStudio buildfix244 — Windows Mixer Parity

## Overview

This build replaces the old read-only mixer ListView with a functional channel-strip mixer and persistent routing model.

## Mixer surface

- Per-track channel strips with:
  - volume fader
  - pan control
  - mute
  - solo
  - record-arm
  - output routing selector
  - post-fader send controls for each return bus
  - real render-derived peak/RMS metering
  - peak hold and persistent clip indication
- Return A / Return B strips with:
  - volume
  - pan
  - mute
  - solo
  - meter
  - stock effect-chain insertion
- Master strip with:
  - master volume
  - master mute
  - playback-updated master meter
  - peak hold
  - clip indicator reset

## Audio-engine routing

The Windows renderer now uses per-track buffers and a real routing graph:

1. Clips/sequencer content render into a track buffer.
2. The track device chain is applied.
3. Track fader and pan are applied.
4. The post-fader track signal is sent either to Master or a selected Return bus output.
5. Independent post-fader send amounts feed Return A/B in parallel.
6. Return device chains process their accumulated inputs.
7. Return fader/pan stages feed Master.
8. Master gain/mute is applied.
9. Metering measures pre-clamp peaks so clipping is visible even though the final safety clamp protects output.

## Metering

- Track and return meters are calculated from actual rendered audio buffers.
- The master meter is refreshed from the live playback sample provider during transport playback.
- Peak hold decays gradually.
- Clip state latches until Reset Clip is pressed.

## Persistence and compatibility

Added project model state:

- `StudioProject.ReturnBuses`
- `StudioProject.MasterVolume`
- `StudioProject.MasterMuted`
- `Track.Sends`
- `Track.OutputBusId`
- `ReturnBus`

Older projects are migrated on load with Return A and Return B plus empty send maps.

## Validation note

The source was structurally checked in the Linux container, but the Windows .NET 8/Visual Studio toolchain is not installed there. Compile and runtime validation should be performed on the Windows VM.
