# LemmingsStudio buildfix234 — Windows VST3 autocompile + completion pass

This pass focuses on the Windows native VST3 helper and removes as much manual build friction as possible.

## Build script / packaging

- `build-windows.ps1` and `build-installer.ps1` now include `-SkipNativeVst3ToolchainBootstrap`.
- By default, when the native VST3 helper is needed, the Windows build script now tries to bootstrap the C++ toolchain instead of silently punting:
  - Git, for JUCE `FetchContent` when `LEMMINGS_JUCE_DIR` is not set.
  - CMake.
  - Visual Studio 2022 Build Tools with C++/CMake/Windows SDK components.
- The helper build now runs a JSONL smoke test before it is bundled.
- `-RequireNativeVst3Host` now fails loudly if the helper cannot be compiled or fails the smoke test.
- The Windows build manifest now records whether `LemmingsVst3Host.exe` was actually bundled.

Recommended full-fat command:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels -RequireNativeVst3Host
```

Use this to avoid automatic winget/toolchain bootstrap:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels -RequireNativeVst3Host -SkipNativeVst3ToolchainBootstrap
```

## Native VST3 helper

- VST3 automation is no longer only block-start granularity.
- C# render now densifies VST3 automation every 64 samples plus exact authored breakpoint frames.
- The native helper splits offline processing blocks at automation event positions so parameter changes are applied inside render blocks instead of only once per block.
- Native helper now reports input/output bus metadata and sidechain capability flags.
- Device metadata records sidechain-capable VST3s clearly instead of pretending sidechain routing is available.

## Still intentionally guarded

- Sidechain/multi-bus routing is detected/reported, but a full routing matrix is still not exposed to users.
- JSONL control remains the command plane; large PCM still uses file-backed `.f32` transport.
- Native helper compilation still requires a Windows C++ toolchain. The script can try to install it via `winget`, but a fresh terminal or reboot may still be needed after Visual Studio Build Tools installation.
