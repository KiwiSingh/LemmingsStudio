# LemmingsStudio buildfix227

Windows parity reset pass after discovering the Windows port still missed major macOS UI/workflow pieces.

## Changes

- Added Windows startup sound playback using the macOS `LemmingsStartup.wav` asset.
- Added `StartupAudio.cs` with NAudio playback for the 24-bit/48 kHz startup WAV.
- Windows splash now plays the startup sting while showing the pre-splash/splash sequence.
- Added `SessionLauncherPanel.cs` for a Session / Clip Launcher workspace.
- Added `ClipInspectorPanel.cs`, replacing the raw property grid with usable clip/track controls.
- Added metronome state to project model and a transport metronome toggle.
- Audio render/export now includes a click track when metronome is enabled.
- Audio clip warp can now be toggled per clip from the inspector.
- Browser seeds stock instruments/effects/agentic categories before user library scans.
- Added `Docs/Buildfix227WindowsParityRoadmap.md` with honest remaining parity gaps.

## Verification

Could not run `dotnet build` in this environment because the container does not have the .NET SDK installed. The patch is source-level and should be validated on the Windows VM with:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels
```
