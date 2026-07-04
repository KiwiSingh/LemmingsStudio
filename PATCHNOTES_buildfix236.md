# Buildfix236 — Windows WASAPI Recording + Expressive MIDI

## Scope
Focused Windows recording/MIDI refinement after buildfix235.

## Added
- WASAPI audio input enumeration in the Audio Recording workspace.
- Input driver selector:
  - WinMM
  - WASAPI shared
  - WASAPI exclusive, with shared fallback where the interface rejects exclusive capture.
- Monitoring mode selector:
  - Off
  - Software monitoring
  - Hardware/direct monitoring note path.
- Recording service now handles WinMM and WASAPI capture formats, including float/24-bit peak metering.
- Recorded WAVs preserve the active capture format rather than forcing only the old WinMM 16-bit format.
- MIDI pitch-bend range control per track.
- Mod-wheel vibrato/depth control per track.
- Live MIDI synth now responds to pitch bend and mod wheel.
- Stock Windows render now applies recorded pitch bend and CC1 mod-wheel expression to Oscillatron, LemmingBass, and the fallback stock synth.
- VST3 live bridge now forwards pitch-bend events to the native host helper.
- MIDI recorder now captures poly pressure in addition to CC, sustain, pitch bend, program change, and channel pressure.

## Notes
- Windows has no universal DAW-safe API for flipping every interface's direct-monitoring switch. The new Hardware/direct monitoring mode deliberately disables software echo and tells the user to enable direct monitoring on their interface/control panel.
- WASAPI exclusive mode is requested when selected, but some drivers reject exclusive capture unless their exact preferred format/buffer contract is used. In that case LemmingsStudio falls back to WASAPI shared instead of failing the take.
