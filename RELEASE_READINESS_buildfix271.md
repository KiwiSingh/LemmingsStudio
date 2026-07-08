# LemmingsStudio buildfix271 — Launch Readiness

Public versions remain:

- macOS: **v2.0**
- Windows: **v2.0**
- visionOS: **v1.0**
- Linux: source-only on GitHub

## Release gates

### Gate A — source/version audit
Run from the repository root:

```bash
./release-audit.sh
```

This is safe to run without Xcode or Visual Studio. It checks version metadata, required source seams, artifact names, and release-critical architecture files.

### Gate B — macOS package verification
On a Mac with Xcode and the required packaging dependencies:

```bash
./release-macos.sh
```

This runs the release build, verifies the produced app bundle version metadata, checks architecture/signature information when the corresponding Apple tools are available, and writes checksums into `release-dist/`.

### Gate C — visionOS package verification
On a Mac with Xcode, XcodeGen, and the visionOS SDK:

```bash
cd Ports/visionOS
./release-visionos.sh simulator
./release-visionos.sh hardware
```

The simulator lane produces `LemmingsStudio-visionOS-v1.0-Simulator.zip`. The hardware lane produces a resignable `LemmingsStudio-visionOS-v1.0.ipa` by building the device app with code signing disabled and packaging it under `Payload/`. End users sign/re-sign that IPA during sideloading.

### Gate D — Windows package verification
On Windows with .NET SDK, PowerShell, and the installer toolchain:

```powershell
cd Ports\Windows
.\release-windows.ps1 -Backend directml -Runtime win-x64
```

This verifies source metadata, compiles the release, invokes the existing installer pipeline, runs release sanity checks when available, and emits SHA-256 hashes.

## Hardware validation checklist

The following cannot be honestly certified by static source inspection and must be exercised before public release:

- visionOS microphone permission and long-form recording
- punch in/out timing under real transport load
- take-folder comp consolidation with multiple long takes
- Write/Touch/Latch automation while the spatial scene is moving
- Integrated Mac Host Mode discovery, pairing, reconnect, and latency
- streamed AU editor interaction for JUCE, native Cocoa, and generic AU views
- project-level Mac bounce for master, selected track, stems, returns, and hosted-plugin return
- authenticated Splice MCP login, preview, download, Fetch-on-Drop, project-local storage, Arrangement insert, and Step Sequencer mapping
- MLX model download, tokenizer load, multimodal inference, cancellation, unload, memory pressure, and thermals
- Wine ARM64 staged-runtime bring-up phases on actual visionOS hardware where policy allows execution
- Simulator ZIP launch in a clean Xcode/Simulator environment
- end-user signing/re-signing of the IPA, installation, and first launch on Apple Vision Pro
- macOS Gatekeeper/notarization behavior appropriate to the chosen distribution path
- Windows clean-machine installer, VST3 host bootstrap, Ollama chat path, and uninstall/reinstall behavior

## Release artifact naming

- `LemmingsStudio-macOS-v2.0.zip` or the chosen signed/notarized macOS container
- `LemmingsStudio-Windows-v2.0-<runtime>-<backend>-Setup.exe`
- `LemmingsStudio-visionOS-v1.0-Simulator.zip`
- `LemmingsStudio-visionOS-v1.0.ipa`

Keep buildfix numbers in release notes and source archives, not in the public semantic version.
