# Buildfix235

Windows implementation pass for:

- audio input recording,
- input monitoring,
- latency-aware recorded clip placement,
- count-in recording,
- MIDI overdub/replace,
- quantize-on-record,
- sustain pedal capture/playback,
- controller/pitch/program/channel-pressure event capture,
- MIDI track creation.

Primary files changed:

- `Ports/Windows/src/LemmingsStudio.Windows/RecordingService.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/AudioRecordingPanel.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/MidiHardwarePanel.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/MidiService.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/AudioEngine.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/Models.cs`
- `Ports/Windows/src/LemmingsStudio.Windows/MainForm.cs`
- `Ports/Windows/native/LemmingsVst3Host/src/Main.cpp`
