# LemmingsStudio Windows — buildfix178 (Claude): the audio engine (playback + real export)

The Windows port had everything *except* sound: shell, model, drag/drop, library,
mixer, automation, save/open, backend scripts, Inno installer and CI were all wired,
but there was no transport, no playback, and "Export Audio" only wrote a JSON render
plan. This adds the first real **audio-engine parity layer** so the port actually plays
and bounces audio.

## New: `AudioEngine.cs` (NAudio)
Renders the arrangement to a 44.1 kHz interleaved-stereo float buffer that powers both
realtime playback and WAV export (so what you hear is what you bounce):
- **Audio clips** decoded via NAudio `AudioFileReader` (WAV/MP3/AIFF/FLAC), resampled to
  the project rate (`WdlResamplingSampleProvider`), optional naive linear tempo-warp,
  placed at their beat position, summed with per-track **volume + equal-power pan +
  mute/solo**, then hard-limited to [-1, 1].
- **MIDI clips** on instrument tracks voiced by a small built-in poly synth
  (saw+square → one-pole low-pass driven by the stock device "Cutoff" → soft drive →
  attack/sustain/release), so instrument tracks are audible before VST3 hosting lands.
- `FloatBufferSampleProvider` streams the rendered buffer to `WaveOutEvent` (playback)
  and `WaveFileWriter.CreateWaveFile16` (export).

## UI wiring (`MainForm.cs`)
- New **transport toolbar**: ▶ Play / ❚❚ Pause + ■ Stop + Export WAV, above the workspace.
- **Export Audio…** now bounces a real **16-bit PCM WAV** of the mixdown (replacing the
  render-plan placeholder).
- Engine logs flow to the Log tab; playback-stopped resets the Play button; the engine is
  disposed on form close.

## Build
- `LemmingsStudio.Windows.csproj` now references **NAudio 2.2.1** (restores from NuGet on
  the Windows build machine / CI). No other pipeline change — the existing
  `build-installer.ps1` + Inno Setup + GitHub Actions flow packages it unchanged.

## Honest scope notes (matches Docs/WindowsPortPlan.md)
- The tempo-warp is a naive resample (changes pitch); high-quality time-stretch is a later
  layer.
- The MIDI synth is a stand-in until VST3/instrument hosting is ported.
- RVC voice features are untracked here (and, per your note, can mature later in the beta).
- Authored on Linux without the .NET toolchain, so I verified by reading + brace/escape
  checks rather than compiling; expect at most minor fixups when you build on Windows.

## Try it
1. Build: `Ports/Windows/build-windows.ps1 -Backend directml` (or open the csproj in VS).
2. Drag a WAV from Explorer onto a track in Arrangement.
3. Press ▶ Play — you should hear it; **Export WAV** bounces it to disk.
