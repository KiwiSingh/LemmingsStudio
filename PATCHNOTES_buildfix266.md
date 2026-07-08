# LemmingsStudio buildfix266

## Full project-level Integrated Mac Host Mode bounce

Public versions are unchanged:

- macOS v2.0
- Windows v2.0
- visionOS v1.0

buildfix266 upgrades the visionOS/macOS Host Mode render path from a single hosted-instance WAV request into a project render manifest and multi-artifact return workflow.

### New bridge transport

The bridge protocol now carries a `requestProjectBounce` request containing:

- project name and BPM
- beat range
- bounce scope
- selected track IDs
- track volume/pan/mute/solo state
- return sends
- return-bus state
- transferable project audio assets
- clip placement, source offsets, source BPM and playback-rate metadata
- active hosted plugin instance ID
- return-bus and hosted-plugin-return inclusion flags
- normalization preference

The Mac returns one or more named WAV artifacts through `projectBounceResult`.

### Supported bounce scopes

- **Master**: one summed project master
- **Selected Track**: one selected-track/submix artifact
- **Stems**: named track stems plus requested return-bus stems and a Mac-hosted plugin return artifact
- **Selected Clip**: routed through the selected-track render path with only the selected audio clip transferred

### Mac-side renderer

The macOS Host Mode renderer:

- decodes transferred project audio assets
- conforms them to the render sample rate
- applies clip placement and source offset
- applies playback-rate adaptation
- applies track gain and pan
- respects mute/solo state
- builds post-fader return sends
- renders simple Delay/Reverb return behavior for the current visionOS return buses
- optionally mixes the active Mac-hosted plugin offline return
- optionally normalizes final artifacts
- returns WAV data to visionOS

### visionOS export handling

Returned artifacts are written to:

`Documents/Exports/`

The Plugin Parity window now exposes:

- scope
- format intent
- include return buses
- include Mac-hosted plugin return
- normalize
- Prepare Plan
- Render on Mac
- progress/status
- saved artifact names

### Validation performed

- Swift parser validation for all modified Swift files
- shell syntax validation for the visionOS packaging script
- ZIP integrity testing before handoff

A full macOS/visionOS SDK build, real-device transfer test, and long-project stress test still require Xcode and Apple hardware.

## Next steps for full macOS parity

1. Recording parity: punch in/out, count-in, pre-roll, take lanes, region slicing, and swipe comping.
2. Automation parity: project persistence, Write/Touch/Latch, curve handles, and spatial gesture recording.
3. Real MLX model loading, model cache, multimodal project/plugin context, and constrained tool execution.
4. Wine ARM64 runtime bring-up, VST3 probe, DSP callback bridge, and editor surface bridge.
5. Final visionOS/macOS parity audit, performance tuning, packaging, and launch hardening.
