# LemmingsStudio Windows — buildfix180 (Claude): export formats (WAV 16/24/32f, AIFF, MP3, FLAC)

The Windows port exported only 16-bit WAV. Now it offers a proper set via a small dialog.

## New (`AudioEngine.cs`)
- `Export(project, path, ExportSettings)` replaces the single-format path (old `ExportWav`
  kept as a 16-bit shim):
  - **WAV** 16-bit / 24-bit PCM / 32-bit float (NAudio `CreateWaveFile16`,
    `SampleToWaveProvider24`, `SampleToWaveProvider`).
  - **AIFF** 16/24-bit PCM (`AiffFileWriter` + `SampleToWaveProvider16/24`).
  - **MP3** (libmp3lame, selectable 128–320 kbps) and **FLAC** (selectable compression)
    via the bundled **ffmpeg**: the engine renders a 32-bit-float temp WAV, then transcodes.
- `FfmpegLocator` finds ffmpeg in order: `LEMMINGS_FFMPEG` env → next to the app →
  `ffmpeg\` or `ffmpeg\bin\` subfolder → PATH (`where ffmpeg`). Clear error if absent
  (WAV/AIFF never need it).

## New (`ExportDialog.cs`)
A small modal: **Format** dropdown, context-sensitive **Bit depth** (WAV 16/24/32f, AIFF
16/24) and **Quality** (MP3 bitrate / FLAC compression), with one-line guidance per format.
Remembers your last choice for the session.

## UI (`MainForm.cs`)
- **Export Audio…** now opens the dialog, then a Save dialog whose filter/extension matches
  the chosen format, then renders.

## Build / packaging
- `build-installer.ps1` stages an optional `ffmpeg.exe` (from `Ports\Windows\ffmpeg\` or
  `$env:LEMMINGS_FFMPEG_SRC`) into the published app; the Inno installer already ships the
  whole publish folder, so it's included automatically. No ffmpeg = WAV/AIFF still work.

## Running the build off an external drive
Answered in chat — short version: since your VM already lives on the external drive, just
build on the VM's `C:` (that's already on the external). For best speed/reliability add a
second virtual disk stored on the external and build there; avoid building across the
`\\Mac\...` shared-folder layer, and stop the drive from sleeping mid-build.

## Honest notes
- MP3/FLAC need ffmpeg present (bundled, on PATH, or via `LEMMINGS_FFMPEG`). On ARM Windows
  use a win-arm64 ffmpeg build.
- Authored on Linux without the .NET toolchain; brace-balanced and NAudio APIs are standard
  2.x, but expect at most minor fixups on first Windows build.

See **Docs/WindowsBuildForNoobs.md** (Exporting audio section) for the user-facing steps.
