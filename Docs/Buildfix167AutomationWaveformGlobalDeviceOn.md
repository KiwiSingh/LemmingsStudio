# Buildfix167 — Automation waveform context, global automation, and Device On/Off

Scope guard: this buildfix does **not** touch the stem splitter logic or stem backend code. The stem splitter was left exactly alone.

## Automation UI context

- Reworked the Automation panel so track lanes are no longer drawn blind.
- Each track automation lane now overlays a faint Arrangement context:
  - audio tracks show clip blocks plus downsampled waveform peaks;
  - MIDI/instrument tracks show clip blocks plus note strips;
  - bar grid remains visible under the automation curve.
- Clicking a lane still adds automation breakpoints, but now the edit position lines up with the actual clip material.

## Global automation

- Added a Global Automation section above track automation.
- Project Tempo can now be edited as a proper global automation lane in the Automation panel.
- The global tempo lane uses the existing project tempo map, so transport playback and audio clip re-warping keep using the same working tempo automation path.
- Tempo points can be tapped into the lane or added numerically by beat/BPM.

## Device On / Device Off automation

- Added an Ableton-style `Device On` automation target for every track insert device.
- Device On lanes use 0 = Off and 1 = On.
- AudioEngine now handles this special automation parameter by toggling the live device bypass state and the backing DeviceModel, rather than trying to send it to a DSP parameter.

## Project persistence

- Track automation lanes are now saved/restored in `.lemmingsproject` files.
- This includes normal parameter automation and the new Device On automation lanes.

## Files changed

- `Sources/LemmingsStudio/Views/AutomationEditor.swift`
- `Sources/LemmingsStudio/Audio/Automation.swift`
- `Sources/LemmingsStudio/Audio/AudioEngine.swift`
- `Sources/LemmingsStudio/App/ProjectDocument.swift`
