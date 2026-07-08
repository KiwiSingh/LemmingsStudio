## buildfix253 — Spatial Editing + Agentic MLX Foundation

- visionOS now includes a dedicated Spatial Editor window for persistent scene-graph transforms.
- Spatial surfaces can be selected, nudged, snapped, reset, duplicated, deleted, hidden, and undone/redone.
- Added a local-first Agentic MLX Lab with quantized multimodal model presets and safe tool-call preview semantics.
- The agent layer proposes tool calls; LemmingsStudio validates and applies them.

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

Current public Mac beta link:

```text
https://bit.ly/LemmingsStudioMac-Beta1
```

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


## visionOS status

The native visionOS port currently includes spatial Arrangement editing, a native Piano Roll and expressive MIDI lanes, a transport-driven Step Sequencer with sample lanes and Print to Arrangement, native AVAudioEngine playback and recording, CoreMIDI input, stock instruments/effects, skins with Liquid Glass-aware surfaces, AUv3 discovery/hosting, an experimental Desktop Plug-in Bridge, and a spatial Mixer with persistent track/send/return/master routing state.

The Desktop Plug-in Bridge currently supports Bonjour discovery, six-digit pairing, macOS Audio Unit discovery/instantiation, MIDI forwarding, generic parameter control, state protocol messages, and experimental stereo PCM return to Vision Pro. Desktop VST3 and experimental Wine providers are planned behind the same protocol abstraction.


## buildfix255 — visionOS parity patch

Adds the next visionOS parity layer around Splice MCP: search/tool-call staging, sample candidate import seams for Arrangement and Step Sequencer, a Fetch-on-Drop toggle, and a dedicated parity roadmap window. macOS and Windows paths remain untouched. See `PATCHNOTES_buildfix255.md` for the running full-parity next steps.


## buildfix256 visionOS note

buildfix256 adds the visionOS-only Gojira Compatibility Lab for sideload/dev-mode plugin compatibility research. It does not alter macOS or Windows build paths. Full macOS parity next steps are tracked in `PATCHNOTES_buildfix256.md`.


## buildfix257 — visionOS Metadata Scanner + Shared Backend Protocol

- Adds metadata-only scanner reports for Gojira Compatibility Lab candidates.
- Adds shared backend capability planning for native AUv3, Mac Companion, macOS component lab, Wine ARM64, and Wine+FEX.
- Keeps all risky local runtime work behind dry-run gates.
- Next parity step: real Mach-O/PE parsing, then Mac Companion desktop-plugin completion.


## buildfix258 — visionOS plugin parity contracts

Adds metadata-only Mach-O/PE parsing, Mac Companion plugin parity contracts, shared parameter automation, streamed editor surface models, and bounce/export dry-run planning for visionOS.

## buildfix260 — Semantic Project Graph

Buildfix260 adds a metadata-only semantic graph for macOS and visionOS. The visionOS build gains a **Semantic Graph** window, and the macOS build gains a matching graph builder from `ProjectDocument`. This is the foundation for MLX agents, Living Project Memory, Host Mode telemetry, and future parity audits.

## buildfix261 — MLX Runtime Core + visionOS Floating MIDI

- Adds the visionOS MLX Runtime window and dry-run model/agent planning.
- Adds a floating visionOS MIDI keyboard for touch/hand-driven note entry.
- Adds Bluetooth/CoreMIDI source summaries for wireless keyboards such as LUMI-style controllers.
- Keeps the input route shared between local instruments, AUv3 instruments, and Mac Host Mode bridge MIDI.

Next parity focus: Living Project Memory, live integrated macOS Host Mode endpoints, streamed plugin editor input, mixer/bounce/export parity, and recording/take-folder parity.


## buildfix262 — Living Project Memory

- Adds the visionOS Living Project Memory window.
- Stores project-local session notes, decisions, rejected ideas, preferences, issues, exports, and AI notes.
- Feeds memory context into Semantic Project Graph and MLX Runtime dry-runs.
- Keeps full macOS parity roadmap visible in patch notes.


## buildfix263 release prep

Public versions remain macOS v2.0, Windows v2.0, and visionOS v1.0. Buildfix263 separates Ollama chat models from agentic models on desktop, upgrades sonic-signature replication into an explicit stock-vs-third-party agent workflow with manual inaccessible-parameter instructions, and adds separate visionOS Simulator ZIP and resignable sideload IPA packaging modes.

## buildfix264 launch parity pass

buildfix264 promotes the visionOS/macOS bridge into Integrated Mac Host Mode: the macOS LemmingsStudio app itself advertises the Bonjour host service and handles remote AU instantiation, MIDI, parameters, state, audio return, editor frame streaming/input, and offline WAV render requests. visionOS also gains automation lane UI/state, recording take folders with comp-take selection, and an executable sideload-only Wine ARM64 probe path. Public versions remain macOS/Windows v2.0 and visionOS v1.0. See `PATCHNOTES_buildfix264.md` for validation limits and remaining parity work.

## buildfix265 — visionOS Splice MCP workflow

buildfix265 completes the next visionOS Splice MCP integration pass: official MCP tool discovery and tool calls, live search result parsing, preview auditioning, authenticated sample download, project-local Splice sample storage, metadata sidecars, Arrangement insertion, Step Sequencer mapping, drag/drop with Fetch on Drop, and BPM-aware playback-rate adaptation for imported loops.

Public version numbers remain macOS v2.0, Windows v2.0, and visionOS v1.0.

## buildfix266 — full Mac Host Mode project bounce

buildfix266 expands Integrated Mac Host Mode from single-instance offline WAV rendering to project-level render manifests and multi-artifact exports. visionOS can request Master, Selected Track, Selected Clip, or Stems workflows, transfer project audio assets and mixer state to the Mac, include return buses and the active Mac-hosted plugin return, and receive named WAV artifacts into `Documents/Exports`.

Public versions remain macOS v2.0, Windows v2.0, and visionOS v1.0.

## buildfix267 — visionOS recording parity

The visionOS build now includes persistent count-in, pre-roll, punch in/out, take-folder recording, region-level comp editing, swipe-style take cycling, playhead splitting, and WAV comp consolidation. See `PATCHNOTES_buildfix267.md`.

## buildfix268 — visionOS automation parity

The visionOS build now persists complete automation lane data and supports Read, Write, Touch, and Latch modes, Hold/Linear/Smooth/Exponential interpolation, editable curve handles, and transport-timed spatial X/Y/Z gesture recording from the Spatial Editor. See `PATCHNOTES_buildfix268.md`.

Public version numbers remain macOS v2.0, Windows v2.0, and visionOS v1.0.


## buildfix269 — real visionOS MLX runtime

buildfix269 replaces the visionOS MLX placeholder path with a package-enabled local VLM runtime using the current MLX Swift LM 3.x integration path. It adds real model loading, retained model containers, project graph + Living Project Memory context, optional streamed plug-in editor image input, constrained JSON tool plans, lane-derived tool allow-lists, explicit confirmation/rejection, cancellable generation tasks, and model unload/resource release. See `PATCHNOTES_buildfix269.md`.

Public version numbers remain macOS v2.0, Windows v2.0, and visionOS v1.0.

## buildfix270 — visionOS Wine ARM64 bring-up

buildfix270 expands the Gojira Compatibility Lab from a single staged Wine smoke-test launcher into a phase-gated ARM64 bring-up pipeline with architecture validation, prefix preparation, loader/DLL/mmap diagnostics, Windows ARM64 probe execution, VST3 enumeration, focused DSP transport and editor bridge experiments, captured logs, timeouts, and termination isolation. The Wine runtime itself is not bundled. See `PATCHNOTES_buildfix270.md` and `Ports/visionOS/WINE_ARM64_STAGING.md`.

Public version numbers remain macOS v2.0, Windows v2.0, and visionOS v1.0.

## buildfix271 launch hardening

The buildfix271 release-prep pass adds `release-audit.sh`, platform-native release verification wrappers, `RELEASE_READINESS_buildfix271.md`, `LAUNCH_PARITY_MATRIX_buildfix271.md`, and `LAUNCH_TEST_PROTOCOL_buildfix271.md`. Public versions remain macOS v2.0, Windows v2.0, and visionOS v1.0; Linux remains source-only on GitHub.

## buildfix272 public visionOS IPA packaging correction

The public visionOS v1.0 hardware artifact is packaged as a resignable sideload IPA. The release builder does not need to export it with a developer/distribution identity. End users sign or re-sign the IPA with their own Apple identity and provisioning workflow during sideloading. The Simulator ZIP path is unchanged, and developer-owned archive workflows remain available separately.

### buildfix276 visionOS scripted-build trust handling

The visionOS build script scopes MLX package trust bypasses to each `xcodebuild` invocation. By default it passes both `-skipPackagePluginValidation` and `-skipMacroValidation` to avoid non-interactive validation failures for the transitive `CudaBuild` plugin and `MLXHuggingFaceMacros` macro target. Set `VISION_SKIP_PACKAGE_PLUGIN_VALIDATION=0` and/or `VISION_SKIP_MACRO_VALIDATION=0` to restore normal validation behavior.

### buildfix277 compile hardening
The first full visionOS Xcode source compile exposed and fixed duplicate observable state, visionOS-unavailable glass API use, MainActor isolation in the Wine probe path, Swift 6 ShapeStyle inference, and stale MLX Agent Panel action names. See `PATCHNOTES_buildfix277.md`.

### buildfix278 compile hardening

The visionOS build now includes the second Xcode source-compile correction batch: Darwin POSIX spawn action initialization, Swift 6 static helper qualification in the Splice MCP client, a valid Living Project Memory event kind for Splice imports, and a Sendable spatial-editor binding closure.

### buildfix282 visionOS compile note
The Step Sequencer now resolves theme accents through `VisionThemeCatalog` and uses a material-backed rounded surface in place of the compiler-problematic `glassBackgroundEffect` expression in this view.

### buildfix286 visionOS simulator launch hardening

The visionOS audio graph now starts lazily and negotiates the active route instead of forcing a stereo graph during app initialization. The visionOS target also carries the 1024x1024 LemmingsStudio `AppIcon` asset source.


### buildfix287
Fixed the visionOS build script on macOS Bash when package-plugin and macro validation bypasses are both disabled.

### buildfix289 visionOS runtime/UI hotfix
The visionOS target now uses a conventional layered image-stack app icon asset, includes local transport controls in the Step Sequencer, and constructs the AVAudioSourceNode render callback from a nonisolated context to avoid Swift 6 executor-isolation traps on the AURemoteIO render thread.

### buildfix291 visionOS note
The visionOS target now explicitly registers `AppIcon` through `CFBundleIcons.CFBundlePrimaryIcon` as well as the asset-catalog build setting. Audio meter taps are also created outside MainActor isolation for AVFAudio realtime service queues.

### buildfix293 visionOS sequencer/transport usability
The primary visionOS editing workspaces now switch inside the main window with a two-row transport/navigation bar. Step Sequencer Print inserts visible SEQ tracks at the top of Arrangement, switches to Arrangement, and disables the live pattern to prevent doubled notes. The metronome is now driven by the audio render clock rather than the 16 ms UI transport timer. See `PATCHNOTES_buildfix293.md`.


### buildfix294

visionOS compile hotfix for metronome button styling under the current Xcode beta SwiftUI toolchain.

### buildfix298 visionOS MIDI clip looping
Arrangement MIDI clips now show miniature note previews and preserve a separate loop source length. Extending a MIDI clip repeats its source pattern visually and during playback instead of appending silence. Step Sequencer prints carry their pattern length into the loop model.

### buildfix299 visionOS general MIDI authoring
Arrangement now supports selecting MIDI-capable tracks, creating a one-bar MIDI clip at the playhead with **New MIDI Clip**, and drag-creating MIDI clips across empty lane ranges. New clips are selected automatically and open directly in Piano Roll for note entry. See `PATCHNOTES_buildfix299.md`.

## buildfix301

visionOS: compact independently placeable spatial MIDI keyboard, context-aware primary Record transport, MIDI keyboard recording into the selected MIDI clip, and Piano Roll auto-framing/visible pitch markers.

## buildfix302 visionOS project persistence

visionOS now supports versioned `.lemmingsproject` packages with embedded audio, samples, and takes; Save, Save As, Open, Recent Projects, 45-second recovery autosave, recovery restore, rollback-safe package replacement, and legacy JSON project import compatibility. See `PATCHNOTES_buildfix302.md`.

## buildfix303 visionOS native export + AI providers + Splice OAuth

The visionOS target now adds native local Song and post-fader Stems export, a provider-neutral agent backend layer, Claude API as the stable minimal-build default AI provider with Keychain credential storage, a Coming Soon Mac AI Bridge provider stub, and a standards-based Splice OAuth/PKCE browser callback flow. No macOS target code is changed in this build. See `PATCHNOTES_buildfix303.md`.

## buildfix304 — visionOS export parity hardening

The visionOS local exporter now shares the live native EQ/Delay/Reverb and Return A/B graph topology through AVAudioEngine offline manual rendering, supports saved AUv3 effect-state rendering, evaluates mixer and send automation per sample frame, provides Pre-Fader/Post-Fader/Post-FX stem modes, configurable return-bus export modes, detailed track/frame progress, and cancellation. See `PATCHNOTES_buildfix304.md`.

## buildfix305 — visionOS hybrid spatial automation

The visionOS target now adds a dedicated Spatial Automation Stage that turns expressive Sway, Pulse, Glide, Strike, Press, and Sculpt-style performance gestures into the same editable breakpoint automation lane data used by conventional Read/Write/Touch/Latch automation. Each lane can map a gesture, scale its min/max range, and invert it; performances remain precisely editable through beat/value, interpolation, and curve-handle controls and stay on the deterministic automation path used by local export. No macOS or Windows target code is changed in this build. See `PATCHNOTES_buildfix305.md`.

### visionOS buildfix309 release hardening

The visionOS port now ships a non-empty three-layer AppIcon image stack and an Xcode-native model-staging build phase. Use `Ports/visionOS/open-in-xcode.sh` for interactive Simulator development with `Command-R`; use `Ports/visionOS/build-visionos.sh ipa` for the unsigned/resignable device IPA workflow.

## buildfix310 — Stock FX + universal spatial automation

The visionOS build now includes a native Stock FX Rack with LemmingsFilter, LemmingCrusher, BurrowDelay, LemmingVerb, and LemmingDrive. Their parameters are registered with the same automation system used by mixer, tempo, spatial and Companion-hosted parameters, so any stock FX parameter can be mapped to Sway, Pulse, Glide, Strike, Press or Sculpt and recorded into editable breakpoint automation.

## buildfix310 hotfix 3 — Per-track stock FX routing

Stock FX are now track inserts rather than a single project-global chain. Select a target track in the visionOS Stock FX Rack, adjust Filter/Crusher/Drive/Delay/Reverb there, then expose that track to Automation. Spatial gesture mappings are addressed by stable track automation identity + effect + parameter, so Sway-style performance automation only changes the intended track.
