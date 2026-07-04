# Buildfix235 — Windows audio recording + MIDI recording polish

Focused implementation pass for the Windows port after the native VST3 work was deferred for final validation.

## Audio recording/input monitoring

- Added `RecordingService` using NAudio `WaveInEvent` + `WaveFileWriter`.
- Added an `Audio Recording` workspace/tab.
- Supports audio input device discovery and refresh.
- Supports target track selection.
- Supports input monitoring through a buffered WaveOut monitor path.
- Supports count-in before capture.
- Supports start-beat placement.
- Supports simple input-latency compensation in milliseconds.
- Writes recorded media beside the project when saved:
  - `<project folder>/Media/Recordings/*.wav`
- Falls back to Documents when the project has not been saved:
  - `Documents/LemmingsStudio/Recordings/<project name>/`
- On stop, creates a real audio clip in Arrangement View using the captured WAV.

## MIDI recording polish

- Expanded MIDI panel with recording mode, quantize, count-in, start beat and length controls.
- Added Overdub/Replace recording modes.
- Added quantize-on-record options: Off, 1/4, 1/8, 1/16, 1/32.
- Added count-in recording.
- Added note recording into clip-relative MIDI notes.
- Added sustain pedal capture and sustain-aware playback extension.
- Added controller/pitch/program/channel-pressure capture into `ProjectClip.MidiEvents`.
- Added VST3 render-side CC/sustain forwarding and pitch-bend forwarding.
- Added MIDI panic cleanup for sustained notes.
- Added `Project → Add MIDI Track`.

## Project model additions

- `StudioProject.CountInEnabled`
- `StudioProject.RecordCountInBars`
- `StudioProject.QuantizeOnRecord`
- `StudioProject.QuantizeGridBeats`
- `StudioProject.MidiRecordMode`
- `ProjectClip.MidiEvents`
- `MidiClipEvent` / `MidiClipEventKind`

## Caveats

- Audio recording uses WinMM/WaveIn for broad compatibility; WASAPI exclusive/low-latency recording can be a later pass.
- Input monitoring is intentionally simple and safe; direct hardware monitoring is still better when available.
- MIDI pitch/CC capture is persisted and forwarded to VST3 render, but the stock synth does not yet fully model pitch-bend/mod-wheel expression.
