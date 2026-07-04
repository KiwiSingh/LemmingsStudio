# Buildfix230 – Windows Native VST3 Helper

This pass adds the first real native Windows VST3 helper executable for the Windows port.

## Why this is a separate executable

VST3 hosting is a native C++ ABI problem. The WinForms/.NET UI should not directly load arbitrary third-party VST3 DLLs inside the main LemmingsStudio process. A crashed plug-in should take down the helper, not the DAW shell. Steinberg's VST3 API is a realtime audio-processing component interface, and VST3 plug-in UI attachment on Windows is done through HWND-backed native views.

## New helper

Path after publish/install:

```text
LemmingsVst3Host.exe
```

Source:

```text
Ports/Windows/native/LemmingsVst3Host/
```

The helper is a JUCE-based C++ app that:

- loads VST3 plug-ins from `.vst3` bundles/files,
- instantiates the first discovered VST3 class,
- opens the plug-in editor window when requested,
- accepts live note-on/note-off/CC/panic events over JSONL IPC,
- processes the plug-in through a lightweight audio callback so VST3 instruments can sound while testing MIDI input.

## Build requirements

The helper needs native C++ build tools:

- Visual Studio 2022 Build Tools
- Desktop development with C++ workload
- CMake tools for Windows
- Git or a local JUCE checkout

To avoid downloading JUCE on each machine, set:

```powershell
$env:LEMMINGS_JUCE_DIR = "C:\Dev\JUCE"
```

Then run:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels -RequireNativeVst3Host
```

Without `-RequireNativeVst3Host`, the main app still builds if the helper cannot be compiled, but native VST3 hosting will be unavailable until `LemmingsVst3Host.exe` is supplied.

## Override helper path

```powershell
$env:LEMMINGS_VST3_NATIVE_HOST = "C:\Path\To\LemmingsVst3Host.exe"
```

or at build time:

```powershell
./build-windows.ps1 -Runtime win-x64 -NativeVst3HostPath "C:\Path\To\LemmingsVst3Host.exe"
```

## Current scope

This is the first native-host implementation pass. It targets live VST3 instruments/editors and MIDI input routing. Full offline render/export through VST3 effects/instruments still needs a follow-up pass that streams project audio blocks through the helper and returns processed PCM buffers to the C# audio engine.
