# LemmingsStudio Windows full-feature parity plan

The goal is full feature parity with the macOS app, not a toy player.

## What buildfix173 added

The Windows tree now has a real native port structure:

- .NET 8 WinForms application shell
- Project model: tempo, key, tracks, clips, devices, automation
- Arrangement canvas with Explorer drag/drop and multi-clip marquee selection
- User Library browser with progressive scan population
- Mixer panel
- Automation panel with global tempo and Device On lane representation
- Project save/open
- Stem backend setup and smoke test hooks
- Installer EXE packaging with Inno Setup

## What buildfix178 adds now (audio engine — first parity layer)

The port is no longer silent. `AudioEngine.cs` (NAudio) renders the arrangement to a
44.1 kHz stereo float buffer and drives both transport playback and WAV export:

- Transport bar (Play / Pause-Stop) above the workspace.
- Audio clips decoded via NAudio (WAV/MP3/AIFF/FLAC), resampled to the project rate,
  optional naive tempo-warp, placed at their beat position, summed with per-track
  volume + equal-power pan + mute/solo.
- MIDI clips on instrument tracks voiced by a small built-in poly synth
  (saw+square → one-pole low-pass from the stock "Cutoff" → attack/sustain/release),
  so instrument tracks are audible before VST3 hosting exists.
- **Export Audio…** now bounces a real 16-bit PCM WAV (what you hear is what you bounce).

This completes steps 1–7's "audio engine playback/export" milestone in the beta path
below; high-quality time-stretch, MIDI-clip warp nuance and plugin instruments remain
later layers.

## Remaining feature parity layers

### 1. Audio engine parity

Port or reimplement:

- timeline playback scheduler
- audio clip decoding/warping
- MIDI clip playback
- mixer graph
- automation application
- export renderer
- clipping detection

Likely Windows tech choices:

- WASAPI for audio I/O
- VST3 SDK / CLAP later for plugins
- managed UI remains WinForms initially, possible WinUI/WPF later

### 2. Plugin hosting

macOS AU hosting does not port to Windows. Windows needs:

- VST3 host path
- plugin scanner
- sandbox/crash isolation later
- parameter automation bridge
- editor window embedding

### 3. Stem splitting / ML backends

Supported target matrix:

- CPU fallback: PyTorch CPU
- NVIDIA: CUDA PyTorch
- AMD / Intel / many NVIDIA devices: ONNX Runtime DirectML
- Intel acceleration: OpenVINO later
- ARM/NPU future: ONNX Runtime QNN / Windows ML where viable

### 4. MIDI and hardware

- WinMM or Windows MIDI Services input/output
- MIDI learn for CC and pitch bend
- MPK Mini IV sanity monitor
- MIDI clock/transport later

### 5. Packaging

- Inno Setup for beta installers
- Optional MSIX later
- Code signing later
- Auto-update later

## Recommended first real beta path

1. Build DirectML installer.
2. Confirm app starts on Windows.
3. Confirm project save/open.
4. Confirm Explorer drag/drop into Arrangement.
5. Confirm backend setup.
6. Confirm stem split smoke test.
7. Port audio engine playback/export next.
8. Port VST3 hosting after audio engine is stable.
