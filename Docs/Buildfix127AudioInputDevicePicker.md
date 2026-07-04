# Buildfix127 — Audio Input Device Picker

Buildfix126 added mono audio-track recording, but it still followed the current CoreAudio default input. That meant a user had to leave LemmingsStudio and switch devices in macOS / Audio MIDI Setup before recording from a Revelator Dynamic, iPhone/Continuity microphone, USB interface, aggregate device, etc.

## What changed

- Added CoreAudio input device discovery in `AudioRecorder`.
- Added an audio input device picker in Settings.
- Added per-audio-track input device selection in Arrangement track headers and track context menus.
- Added the same input device picker to the Recording panel.
- Track recording now selects the chosen CoreAudio input device before installing the input tap.
- Per-track audio input device UID/name is saved in project files.
- Duplicated tracks preserve input device, input monitor, and input channel.

## Behavior

- `System Default` keeps following macOS' current default input.
- Picking a named device, such as a Revelator Dynamic or iPhone microphone, records from that device without making the user manually change Audio MIDI Setup first.
- The existing channel picker remains per-track, so a multi-channel interface can still use Input 1, Input 2, etc.
- Recorded clips include the input device and channel in their display name.

## Limitations

This is still mono-per-track capture. Stereo input pairs and multi-input simultaneous recording can be layered later.

Splice, Sound Agent, Demucs, AU hosting, Mixer FX, Piano Roll, metronome/count-in timing, and stem code were not touched.
