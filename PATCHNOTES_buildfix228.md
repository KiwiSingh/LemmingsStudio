# LemmingsStudio buildfix228 — Windows VST3 + MIDI native pass 1

This build starts the feature-parity work that should have happened before the Windows port was described as real.

## VST3 hosting/editor pass

- Added a Windows VST3 scanner for common VST3 locations:
  - `Program Files/Common Files/VST3`
  - `Program Files (x86)/Common Files/VST3`
  - user/AppData VST3 locations
  - extra roots via `LEMMINGS_VST3_PATHS`
- Added VST3 project/device metadata:
  - plug-in format
  - plug-in path
  - manufacturer
  - editor bridge information
- Added VST3 device slots to the Windows Device Rack.
- Added **Scan/Add VST3 Plug-in…** and **Add VST3 From File…** in the Device Rack.
- Added **Editor** button on VST3 device cards.
- Added external editor bridge discovery:
  - `LEMMINGS_VST3_HOST`
  - Carla
  - Element
- If no host is available, LemmingsStudio now explains exactly what is missing and can open the plug-in location in Explorer.

Important honesty note: this is not pretending to be a completed in-process Steinberg VST3 audio host. VST3 slots are now discovered, stored, shown, and editor-bridged. Actual in-process audio/MIDI processing still needs a native VST3 host layer.

## MIDI pass

- Replaced the old MIDI status stub with a real MIDI / Hardware panel.
- Added WinMM/NAudio MIDI input discovery.
- Added MIDI output discovery.
- Added open/refresh controls for MIDI devices.
- Added live MIDI audition through a lightweight built-in synth.
- Added target-track selection for live audition.
- Added record-armed MIDI capture to project MIDI clips.
- Added note-on/note-off logging.
- Added CC logging.
- Added MIDI panic for live audition.
- Added MIDI Learn buttons to device parameters.
- Learned CC mappings are stored on device slots and applied live to parameters.

## Changed files

- `Ports/Windows/src/LemmingsStudio.Windows/Models.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/MainForm.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/Features/DeviceRackPanel.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/Vst3PluginService.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/MidiService.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/MidiHardwarePanel.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/LiveMidiSynth.cs`

## Still not complete

- Native in-process VST3 audio processing/editor embedding is still not implemented.
- VST3 plug-ins are bypassed during offline render until the native host layer exists.
- MIDI clock/transport sync is not done yet.
- Controller maps such as MPK Mini IV presets still need a dedicated pass.
