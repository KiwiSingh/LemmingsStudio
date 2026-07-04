# Buildfix 215 — Windows ffmpeg Auto-Install/Bundle

The Windows build pipeline now attempts to bundle `ffmpeg.exe` automatically so MP3 and FLAC export work out of the box.

## Behavior

`Ports/Windows/build-windows.ps1` forwards ffmpeg options to `build-installer.ps1`. The installer build resolves ffmpeg in this order:

1. `-FfmpegSource <path>`
2. `LEMMINGS_FFMPEG_SRC`
3. `Ports/Windows/ffmpeg/ffmpeg.exe`
4. `Ports/Windows/ffmpeg/<runtime>/ffmpeg.exe`
5. `ffmpeg.exe` already on `PATH`
6. automatic download into `Ports/Windows/ffmpeg/<runtime>/ffmpeg.exe`

The resolved binary is copied into the publish folder as `ffmpeg.exe`, which means the Inno installer bundles it automatically with the app files.

## New switches

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-arm64
./build-windows.ps1 -Backend cpu -Runtime win-arm64 -FfmpegSource C:\Tools\ffmpeg\bin\ffmpeg.exe
./build-windows.ps1 -Backend cpu -Runtime win-arm64 -SkipFfmpeg
```

## Notes

WAV and AIFF export do not require ffmpeg. MP3 and FLAC export use the bundled executable when present, then fall back to `LEMMINGS_FFMPEG`, app-local ffmpeg paths, or PATH at runtime.
