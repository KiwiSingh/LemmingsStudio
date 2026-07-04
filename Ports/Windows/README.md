# LemmingsStudio Windows Port

This is the native Windows port source tree.

## Current status

This is no longer only a launcher preview. It now contains a full-fat Windows source scaffold:

- Native .NET 8 WinForms app shell
- Arrangement view with Explorer drag/drop and multi-clip selection
- Browser/User Library scan with progressive population
- Project save/open for `.lemmingsproject`
- Mixer panel
- Automation panel with global tempo and Device On lanes
- Device/clip inspector
- Backend setup and stem split test scripts
- Inno Setup installer packaging

The macOS app is still the full reference DAW implementation. The Windows code is structured so the missing parity pieces can be ported without throwing away this build pipeline.

## Build installer

```powershell
.\Ports\Windows\build-installer.ps1 -Backend directml -Runtime win-x64
```

Installer output:

```text
Ports\Windows\artifacts\installer
```

## Backend choices

- `directml`: best default for AMD, Intel, and broad GPU compatibility
- `cuda`: NVIDIA CUDA path
- `cpu`: slow but safest fallback

## Local development

Open the C# project:

```text
Ports\Windows\src\LemmingsStudio.Windows\LemmingsStudio.Windows.csproj
```

in Visual Studio 2022 or JetBrains Rider.
