# LemmingsVst3Host

Native Windows VST3 helper for LemmingsStudio.

This is intentionally out-of-process so third-party VST3 crashes do not take down the main WinForms app. The helper is built with JUCE and communicates with the managed app via JSONL on stdin/stdout.

## Build manually

```powershell
cd Ports\Windows\native\LemmingsVst3Host
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target LemmingsVst3Host
```

Set `LEMMINGS_JUCE_DIR` to use a local JUCE checkout instead of FetchContent.

## buildfix234 auto-build notes

The top-level Windows build scripts now try to compile this helper automatically.

Recommended command:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels -RequireNativeVst3Host
```

If Git, CMake, or Visual Studio 2022 Build Tools are missing, the script will attempt to install them through `winget`. Use `-SkipNativeVst3ToolchainBootstrap` if you prefer to install the toolchain manually.

Set `LEMMINGS_JUCE_DIR` to a local JUCE checkout/cache if you do not want CMake `FetchContent` to download JUCE.
