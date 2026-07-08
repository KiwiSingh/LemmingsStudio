<p align="center">
  <img src="./LemmingsStudioSplash.png" alt="LemmingsStudio splash screen" width="240" />
</p>

<h1 align="center">LemmingsStudio</h1>

<p align="center">
  A chaotic, AI-assisted, cross-platform DAW experiment by MagmaVance LLC.
</p>

<p align="center">
  <strong>macOS beta available now.</strong><br />
  Windows is in release-candidate validation, visionOS is in active native development, and Linux is planned after the visionOS foundation stabilizes.
</p>

---

## What is LemmingsStudio?

LemmingsStudio is an experimental music-production workstation built around familiar DAW workflows, stock instruments/effects, automation, audio/MIDI editing, sample workflows, and agentic music-production ideas.

The project started as a “what if I just built the thing?” experiment and has grown into a real beta app with macOS support, a Windows parity candidate, and an actively developing native visionOS port.

LemmingsStudio is still beta software. Expect rough edges, especially around third-party plug-ins, backend setup, and platform-specific audio/MIDI behavior.

## Current feature highlights

- Arrangement View
- Step Sequencer workflows
- Piano Roll editing
- Audio clips and MIDI clips
- Stock instruments, including Oscillatron and LemmingBass
- Stock effects and device rack workflows
- Track, clip, device, tempo, and VST3 automation paths
- Bounce/freeze/export workflows
- Audio recording and MIDI recording on Windows parity builds
- WASAPI/WinMM recording paths on Windows
- AU plug-in hosting on macOS
- Native VST3 hosting and native helper infrastructure on Windows
- Native visionOS Arrangement editing, transport, Piano Roll, Step Sequencer, stock synthesis/effects, MIDI input, and audio recording foundations
- Native AUv3 discovery and hosting on visionOS, including generic parameter controls and document-state restoration
- Liquid Glass-aware visionOS interface surfaces and the full LemmingsStudio skin set
- Desktop plug-in bridge architecture for desktop-only AU/VST3 plug-ins from visionOS
- Splice integration experiments
- Discord Rich Presence
- Agentic music-production features
- Experimental stem-splitting/model-backed workflows where supported

## Downloading binaries

Large binary builds are not intended to live in this Git repository.

GitHub repositories are best kept source-only for this project because the packaged app bundles, model caches, ffmpeg binaries, Python backends, and installer artifacts can become very large.

Planned binary distribution strategy:

- GitHub repository: source code, scripts, docs, issues, and roadmap.
- GitHub Releases: small release notes and links where possible.
- External hosting: large `.dmg`, `.exe`, model-pack, and full-fat installer downloads.

All latest builds (currently only macOS and visionOS) can be found [here](https://lemmingsstudio.online/downloads/).

Project/demo video:

```text
https://www.youtube.com/watch?v=Y3yoBzyWPgw
```

## Repository layout

```text
.
├── Sources/LemmingsStudio/          # Main Swift/macOS app source
├── Ports/Windows/                   # Windows port, installer scripts, native helper projects
├── Ports/visionOS/                  # Native visionOS app, spatial UI, audio/MIDI foundation
├── Scripts/                         # macOS helper/build scripts
├── Docs/                            # Build notes, parity notes, backend notes, historical patch notes
├── Package.swift                    # Swift package definition
├── build.sh                         # macOS build helper
└── LemmingsStudioSplash.png         # README splash image
```

## macOS build instructions

### Requirements

- macOS on Apple Silicon is recommended.
- Xcode command-line tools.
- Swift toolchain included with Xcode.
- Optional: Carla/Homebrew dependencies if testing plug-in bridge workflows.
- Optional: Python/ML dependencies if testing backend stem/model features.

Install Xcode command-line tools:

```bash
xcode-select --install
```

### Build

From the repository root:

```bash
chmod +x ./build.sh
./build.sh
```

For direct SwiftPM builds:

```bash
swift build -c release
```

Depending on the current build script revision, the packaged app output may be placed under `.build/`, `dist/`, or a script-created release folder. Check the terminal output after the build completes.

### macOS bundle metadata

The current app metadata uses:

```text
Bundle identifier: com.magmavance.LemmingsStudio
Version: 1.1
```

## Windows build instructions

The Windows build lives under:

```text
Ports/Windows
```

### Requirements

- Windows 10/11.
- .NET SDK 8.
- PowerShell.
- Inno Setup 6 for installer builds.
- Visual Studio 2022 Build Tools with Desktop C++/CMake components if building the native VST3 helper.
- Internet access during first build if the script needs to download ffmpeg, VC++ redistributable, JUCE, Python, or model/backend assets.

Recommended Windows x64 build command:

```powershell
cd Ports\Windows
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels -RequireNativeVst3Host
```

Native Windows ARM64 build command:

```powershell
cd Ports\Windows
./build-windows.ps1 -Backend cpu -Runtime win-arm64
```

Important: the native `win-arm64` build intentionally disables some Demucs/stem-splitting paths because the Windows ARM64 Python audio/ML ecosystem does not currently provide all required wheels reliably. Use the `win-x64` build under Windows-on-ARM emulation for fuller backend compatibility.

### Useful Windows build flags

```powershell
-SkipFfmpeg
-FfmpegSource "C:\Path\To\ffmpeg.exe"
-BundleModels
-ModelNames htdemucs
-RequireNativeVst3Host
-SkipNativeVst3Host
-SkipNativeVst3ToolchainBootstrap
-NativeVst3HostPath "C:\Path\To\LemmingsVst3Host.exe"
```

### Installer output

Windows build artifacts are usually written under:

```text
Ports/Windows/artifacts/
```

The exact installer path is printed by the build script after packaging completes.


## visionOS build instructions

The native visionOS build lives under:

```text
Ports/visionOS
```

### Requirements

- A Mac running a recent Xcode release with the visionOS SDK installed.
- XcodeGen.
- Apple Vision Pro Simulator or a paired Apple Vision Pro device for device testing.
- Microphone permission for native audio recording.

Install XcodeGen with Homebrew:

```bash
brew install xcodegen
```

Install the visionOS platform runtime when needed:

```bash
xcodebuild -downloadPlatform visionOS
```

### Generate and build

```bash
cd Ports/visionOS
xcodegen generate
./build-visionos.sh simulator
```

Other supported build modes:

```bash
./build-visionos.sh generic-simulator
./build-visionos.sh device
./build-visionos.sh archive
./build-visionos.sh list
```

Direct `xcodebuild` example:

```bash
cd Ports/visionOS
xcodegen generate

xcodebuild \
  -project LemmingsStudioVision.xcodeproj \
  -scheme LemmingsStudioVision \
  -configuration Debug \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  build
```

### Run the prebuilt Simulator `.app` bundle

The visionOS Simulator release is distributed as a ZIP containing a prebuilt `LemmingsStudio.app`. This build is for the Apple Vision Pro Simulator only; it cannot be installed on physical Apple Vision Pro hardware.

#### Requirements

- A Mac with Xcode and the visionOS Simulator runtime installed.
- An Apple Vision Pro Simulator created and available in Xcode.
- Enough free disk space for the extracted app bundle and Simulator data.

Download the Simulator ZIP, then extract it in Finder by double-clicking the archive, or from Terminal:

```bash
mkdir -p ~/Downloads/LemmingsStudio-visionOS-Simulator
unzip LemmingsStudio-visionOS-v1.0-Simulator.zip \
  -d ~/Downloads/LemmingsStudio-visionOS-Simulator
```

After extraction, locate `LemmingsStudio.app`.

#### Install with Xcode / Device Hub

1. Open Xcode.
2. Start an Apple Vision Pro Simulator.
3. In Xcode 27 or later, open **Xcode > Open Developer Tool > Device Hub** (or use **Manage Devices…** from the run-destination menu). On older Xcode releases, use **Window > Devices and Simulators**.
4. Select the running Apple Vision Pro Simulator.
5. Use the app-management controls to install `LemmingsStudio.app`; where supported, you can drag the `.app` bundle into the installed-apps area.
6. Launch LemmingsStudio from the Simulator Home View.

Apple documents Device Hub as the place to manage simulated and physical devices and their installed apps:

```text
https://developer.apple.com/documentation/xcode/device-hub
```

#### Terminal fallback with `simctl`

When the Xcode UI is inconvenient, install the extracted app directly into the currently booted Simulator:

```bash
open -a Simulator

xcrun simctl bootstatus booted -b

APP_PATH="$HOME/Downloads/LemmingsStudio-visionOS-Simulator/LemmingsStudio.app"
BUNDLE_ID="com.magmavance.LemmingsStudioVision"

xcrun simctl uninstall booted "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted "$BUNDLE_ID"
```

If `booted` reports that no Simulator is running, start an Apple Vision Pro Simulator from Xcode first and rerun the commands.

### Sideload the unsigned IPA on Apple Vision Pro

The public hardware artifact is a **resignable unsigned IPA**. It is not ready to install as downloaded: the end user must sign or re-sign it with their own Apple identity, certificate, App ID, and provisioning profile before Xcode can install it on Apple Vision Pro.

Apple's supported device-development workflow requires pairing the Vision Pro with Xcode, enabling Developer Mode on the headset, and using a valid development signing setup. Apple documents the relevant device and Developer Mode workflows here:

```text
https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices
```

#### Step 1 — Prepare Xcode and the Vision Pro

1. Install Xcode with the matching or newer visionOS SDK.
2. In **Xcode > Settings > Accounts**, add the Apple Account you will use for signing.
3. Pair the Apple Vision Pro with the Mac through Xcode's device-management UI.
4. Enable **Developer Mode** on Apple Vision Pro when prompted, then restart/confirm on the headset if visionOS requests it.
5. Confirm that the Vision Pro appears as an available physical run destination in Xcode.

A free Apple developer account can be used to test apps on your own devices, but Apple states that Personal Team provisioning profiles expire after 7 days, so the app must be signed and installed again after expiration. Paid Apple Developer Program accounts avoid the Personal Team 7-day limit and are strongly recommended for regular use.

Apple membership comparison:

```text
https://developer.apple.com/support/compare-memberships/
```

#### Step 2 — Create a signing shell project

Because the downloaded IPA is unsigned, create a small temporary visionOS app in Xcode to make Xcode generate signing assets for your Apple Account:

1. Choose **File > New > Project**.
2. Create a basic **visionOS App**.
3. Give it a unique bundle identifier that belongs to you, for example `com.yourname.LemmingsStudioLocal`.
4. Open **Signing & Capabilities**, select your Team, and leave **Automatically manage signing** enabled.
5. Select your paired Apple Vision Pro as the run destination and run the shell app once.

This step confirms that Xcode can provision and install a development-signed visionOS app on your headset before you re-sign LemmingsStudio.

#### Step 3 — Re-sign the LemmingsStudio IPA

A community-tested Apple Vision Pro workflow is:

1. Use a local IPA signing tool on the Mac that can sign with your Apple Development certificate and provisioning profile. One community-tested example is **iOS App Signer 2**.
2. Select the downloaded `LemmingsStudio-visionOS-v1.0.ipa` as the input file.
3. Select your Apple Development signing certificate.
4. Select the provisioning profile created for your temporary visionOS shell project.
5. Make sure the re-signed app uses the same application identifier/bundle identifier as that provisioning profile. This normally means replacing the original bundle identifier with the unique identifier from your shell project.
6. Export a newly signed IPA.

The Vision Pro community has reported this general flow — create and run a shell visionOS project, re-sign the IPA with the shell project's team/profile and bundle identifier, then install the signed IPA from Xcode's device-management window:

```text
https://www.reddit.com/r/VisionPro/comments/1aihm7s/sideloaded_uyou_and_apollo_using_xcode/
```

> Only install LemmingsStudio IPA files obtained from the official project release source. Re-signing does not make an untrusted IPA safe.

#### Step 4 — Install the signed IPA on Vision Pro

1. Open **Device Hub** in Xcode 27 or later, or **Window > Devices and Simulators** in older Xcode releases.
2. Select the paired Apple Vision Pro.
3. In the installed-apps section, use the add/install control or drag the newly signed IPA into the app list.
4. Wait for installation to finish.
5. If visionOS asks you to trust the development identity/profile, approve it in the device-management settings on the headset.
6. Launch LemmingsStudio from the Vision Pro Home View.

Community reports specifically describe installing the re-signed IPA from Xcode's device list after pairing and enabling Developer Mode. The Apple Vision Pro must remain compatible with the SDK/deployment target used by the release build.

#### Troubleshooting physical-device installation

- **`ApplicationVerificationFailed` / signature errors:** the IPA was not signed correctly, the bundle identifier does not match the provisioning profile, or embedded signatures/entitlements are inconsistent.
- **Provisioning profile expired:** re-sign and reinstall; Personal Team profiles expire after 7 days.
- **Device not shown in Xcode:** verify pairing, Developer Mode, Wi-Fi/network reachability, and Xcode/visionOS compatibility.
- **Install succeeds but launch fails immediately:** capture the device console and crash report in Xcode Device Hub and report the exact visionOS version and release build.
- **Do not try to install the Simulator `.app` on hardware:** use the signed IPA for Apple Vision Pro hardware and the Simulator ZIP only for the visionOS Simulator.

The visionOS port is native SwiftUI/AVFoundation code. It currently includes project opening, transport, spatial Arrangement editing, clip move/trim/split workflows, a native Piano Roll with expressive MIDI lanes, a transport-driven Step Sequencer with Print to Arrangement, native stock synthesis/effects, CoreMIDI input, microphone recording, Liquid Glass-aware surfaces, detachable spatial control windows, the LemmingsStudio skin set, and a first native AUv3 host.

The AUv3 host currently supports component scanning, asynchronous instantiation, one active instrument/generator/effect slot, parameter-tree enumeration, a generic spatial parameter editor, optional plug-in-provided custom UI hosting, MIDI forwarding for instruments, and `fullStateForDocument` persistence in `.lemmings` projects. Multi-slot spatial device-rack work remains planned.

Desktop-only plug-ins such as conventional macOS AU components or Windows/macOS VST3s are planned through the Lemmings Desktop Plug-in Bridge rather than by copying desktop plug-in bundles directly onto visionOS.

## Large files and release assets

Do not commit generated app bundles, installers, `.dmg` files, model caches, Python environments, or generated media into the repository.

Suggested pattern:

```text
GitHub repo       → source code only
GitHub Releases   → release notes + small assets + external download links
External storage  → large DMG/EXE/model-pack downloads
```

Good candidates for external hosting:

- Mac `.dmg` installers
- Windows `.exe` installers
- full-fat Windows builds with Python/PyTorch/Demucs caches
- optional RVC/model packs
- generated splash/video assets if they become large

## Current platform status

### Windows

The Windows port has completed the planned parity implementation passes covering Device Rack workflows, Splice/sample workflows, bounce/freeze/consolidate, Arrangement editing, Piano Roll/MIDI polish, Mixer routing, recording, export diagnostics, native VST3 helper infrastructure, and release hardening.

The remaining Windows work is validation and bug fixing on real Windows hardware/VMs, especially third-party VST3 behavior, audio-interface behavior, installer behavior, and backend ML dependency setup.

### visionOS

The native visionOS port is in active development. Current work includes:

- `.lemmings` project opening
- transport and timeline seeking
- spatial Arrangement editing
- gaze/pinch-oriented clip move and trim interactions
- detachable inspector and volumetric control surfaces
- native stock synthesis and effects
- MIDI input
- microphone recording
- Liquid Glass-aware interface surfaces
- LemmingsStudio skin parity
- native AUv3 discovery/hosting with generic controls, custom UI hosting, MIDI forwarding, and document-state restoration
- Bonjour Desktop Plug-in Bridge with pairing, AU discovery/instantiation, MIDI, parameters, state messages, and experimental stereo audio return
- spatial Mixer with track strips, post-fader sends, Return A/B, master control, metering, output routing, and a volumetric overview

The remaining major parity areas are automation editing, multi-slot device racks and isolated per-track instrument buses, full bounce/freeze/export parity, Splice/sample workflow parity, richer recording workflows, agentic/ML features, and release hardening on real Vision Pro hardware.

## Known beta caveats

- Third-party plug-in behavior may vary by vendor and platform.
- Windows VST3 hosting should be validated plug-in by plug-in before the Windows build is treated as production-ready.
- visionOS is still an active native port; AUv3 hosting, the first desktop bridge audio return, and spatial Mixer routing are implemented, but full DAW parity is not complete yet.
- Some ML/audio features depend on large Python/PyTorch/Demucs/RVC dependencies.
- Native Windows ARM64 support is improving, but x64 remains the safer target for full backend compatibility.
- The chatbot/model integration is still early; other agentic features are further along.

## Contributing

Contributions, bug reports, test reports, and platform-specific fixes are welcome once the project is published.

Useful issue reports should include:

- OS version and architecture
- LemmingsStudio version/build
- exact build command used
- audio interface/MIDI device details if relevant
- plug-in name/version/path if relevant
- logs or screenshots
- steps to reproduce

## License

LemmingsStudio is available under the GNU General Public License v3. See `LICENSE.md` for further details.

## Copyright

© MagmaVance LLC. All rights reserved.
