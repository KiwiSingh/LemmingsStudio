# LemmingsStudio buildfix237 — Windows export diagnostics + dynamic refresh-rate splash

## Windows: render/export parity smoke diagnostics

- Added `WindowsParityDiagnosticsForm` under **Tools → Windows Parity Diagnostics…**.
- Diagnostics panel reports:
  - Windows/runtime/process architecture
  - build manifest contents
  - detected monitor refresh rate
  - native VST3 host status
  - ffmpeg presence
  - track / clip / step sequencer / VST3 summary
- Added one-click render/export smoke tests for:
  - WAV 24-bit
  - AIFF 24-bit
  - MP3 320 kbps via ffmpeg
  - FLAC via ffmpeg
- Smoke tests export into a timestamped temp folder and log PASS/FAIL without crashing the app.

## Windows: dynamic MagmaVance pre-splash refresh-rate selection

- Added `DisplayRefreshRateDetector` using `EnumDisplaySettings` to query the current primary display refresh rate.
- `StartupSplashForm` now selects the nearest available pre-splash frame set:
  - `PreSplashFrames_<fps>`
  - fallback to `PreSplashFrames_60`
  - fallback to legacy `PreSplashFrames`
- Timer interval is derived from the selected FPS.
- If querying fails, refresh detection falls back to 60 Hz.
- Added `Assets/MagmaVancePreSplash.mp4` as the source video for future Windows frame regeneration.
- Added `scripts/generate-presplash-variants.ps1` to generate frame sets for common consumer refresh rates:
  - 60, 75, 90, 120, 144, 165, 240 Hz
- Windows build script now runs the generator before `dotnet publish` when ffmpeg is available. If ffmpeg is unavailable, existing frames are used and 60 fps remains the safe fallback.

## macOS: dynamic MagmaVance pre-splash refresh-rate selection

- Added bundled `MagmaVancePreSplash_<fps>.mp4` variants for:
  - 60, 75, 90, 120, 144, 165, 240 fps
- `MagmaVancePreSplashAsset` now queries `NSScreen.main.maximumFramesPerSecond` and selects the nearest bundled FPS variant.
- If querying fails, macOS falls back to the 60 fps variant, then the original `MagmaVancePreSplash.mp4`.
- Added `Scripts/generate-presplash-variants.sh` for regenerating macOS MP4 variants from the source asset.

## Notes

- Windows frame variants beyond 60 fps are generated at build time rather than all being committed into the source zip, to keep the repository from ballooning unnecessarily.
- The Windows diagnostics panel is intended as the next verification surface before doing VST account/plugin login testing.
