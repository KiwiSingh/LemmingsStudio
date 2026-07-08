# LemmingsStudio for visionOS

Native SwiftUI/AVFoundation visionOS port of LemmingsStudio.

## Current status

The visionOS port now includes the spatial editing, native audio/MIDI, AUv3 hosting, desktop bridge, spatial mixer, Piano Roll, and Step Sequencer foundations:

- `.lemmings` project opening
- transport and timeline seeking
- Arrangement View
- gaze/pinch-friendly clip selection
- pinch-drag clip movement
- left/right trim handles
- split, duplicate, and delete
- snap/grid choices
- horizontal magnification zoom
- vertical track scaling
- native AVAudioEngine graph
- project audio-clip playback scheduling
- polyphonic Oscillatron and LemmingBass preview/playback voices
- stock 3-band EQ, delay, and reverb chain
- CoreMIDI input discovery and live note input
- microphone recording into `Documents/LemmingsStudio/Recordings`
- detachable native Audio Control window
- full LemmingsStudio skin catalog
- Liquid Glass-aware custom control surfaces with visionOS compatibility fallback
- detachable Clip Inspector window
- experimental volumetric Spatial Control Deck
- desktop plug-in bridge protocol seam
- experimental Wine provider seam behind the bridge contract
- native Piano Roll with note add/select/move, quantize, humanize, transpose, ghost-note and scale helpers
- persistent expressive MIDI lanes for velocity, CC1 modulation, pitch bend, and sustain
- transport-driven Step Sequencer with variable step count, swing, per-lane volume/pan, sample assignment, and live playhead indication
- Print to Arrangement that produces ordinary editable MIDI clips

## Liquid Glass and skins

The visionOS interface keeps timeline/project content visually primary while applying glass to controls, inspectors, and detachable tool surfaces. On SDKs that expose the newer Liquid Glass APIs, custom controls use interactive `glassEffect`; earlier visionOS targets fall back to native `glassBackgroundEffect` surfaces.

Available skins:

- Liquid Glass
- World Cup 2026
- Cyberpunk 2077-ish
- Hot Pink
- Anime Racing
- Elemental Fantasy
- Alien Club
- Spatial Future
- Lemmings
- Hamster After Dark
- Kitty and Buds

The skin picker is available from the main toolbar and the detachable Skin Gallery window.

## Requirements

- Apple Silicon Mac recommended
- Full Xcode with a visionOS SDK/runtime
- XcodeGen
- Homebrew optional; the build script can use it to install XcodeGen

Check the active Xcode:

```bash
xcode-select -p
xcodebuild -version
```

List installed SDKs:

```bash
xcodebuild -showsdks
```

Install/download the visionOS platform runtime when needed:

```bash
xcodebuild -downloadPlatform visionOS
```

## Build with xcodebuild

The wrapper script generates the Xcode project with XcodeGen and then invokes `xcodebuild`.

```bash
cd Ports/visionOS
./build-visionos.sh simulator
```

Other modes:

```bash
./build-visionos.sh generic-simulator
./build-visionos.sh device
./build-visionos.sh archive
./build-visionos.sh list
```

Override the simulator/device destination:

```bash
VISION_DESTINATION='generic/platform=visionOS Simulator' \
./build-visionos.sh simulator
```

Direct invocation after generating the project:

```bash
cd Ports/visionOS
xcodegen generate

xcodebuild \
  -project LemmingsStudioVision.xcodeproj \
  -scheme LemmingsStudioVision \
  -configuration Debug \
  -destination 'generic/platform=visionOS Simulator' \
  build
```

For a generic simulator build useful in CI:

```bash
xcodebuild \
  -project LemmingsStudioVision.xcodeproj \
  -scheme LemmingsStudioVision \
  -configuration Debug \
  -destination 'generic/platform=visionOS Simulator' \
  build
```

For a release archive:

```bash
./build-visionos.sh archive
```

Device builds and archives still require appropriate signing/provisioning configuration.

## Native audio notes

The buildfix248 engine is intentionally local-first:

- MIDI clips drive native stock synthesis during transport.
- Audio clips schedule from project media paths and honor clip source offset/length semantics.
- External CoreMIDI note input can audition the selected stock instrument.
- The Audio Control window exposes low/mid/high EQ, delay wet mix, reverb wet mix, instrument selection, panic, and recording controls.
- Microphone takes are written as CAF files to the app Documents recording directory.

This is the first native audio foundation, not yet the final full mixer/device graph. AUv3 discovery/hosting is the next major plug-in step.

## Interaction notes

The Arrangement interaction model is designed around visionOS indirect input:

- look at a clip to target it,
- pinch to select,
- pinch-and-drag the clip body to move,
- drag either edge handle to trim,
- use context actions or the detachable Inspector for split/duplicate/delete.

The Spatial Control Deck remains experimental. Later passes can evolve it into spatial mixer, device, and bridge control surfaces.

## Native AUv3 hosting (buildfix249)

The visionOS port now includes a first native Audio Unit host built around `AVAudioUnitComponentManager`, asynchronous `AVAudioUnit` instantiation, AU parameter-tree discovery, optional plug-in-provided UI embedding, MIDI forwarding for hosted instruments, and `fullStateForDocument` persistence in the `.lemmings` project model.

Current scope is intentionally one active native AU slot at a time. This is a foundation pass for real-device validation before the spatial Device Rack grows into multiple instrument/effect slots.

Use the **Plug-ins** button in the main visionOS toolbar to scan and load components. Generic parameters appear in the **Plug-in Controls** window; when the AU provides its own view controller, the same window can switch to the plug-in UI.


## Desktop Plug-in Bridge (buildfix250)

The visionOS app can discover a running LemmingsStudio instance on the same local network through Bonjour service `_lemmings-plugin._tcp`. The Mac build starts the bridge service when the main app window appears.

1. Launch the macOS LemmingsStudio app.
2. Launch the visionOS build and open **Desktop Bridge**.
3. Select the discovered Mac.
4. The Mac displays a six-digit pairing code. Enter it on Vision Pro.
5. Refresh the plug-in list, load a desktop Audio Unit, and optionally enable desktop audio return.

The current transport uses newline-delimited JSON control messages over TCP and base64 float32 stereo PCM chunks for the first audio-return implementation. This is intentionally debuggable; a lower-overhead binary/QUIC audio path is expected after real-device validation.

## Piano Roll and Step Sequencer (buildfix252)

The Piano Roll operates on the selected Arrangement MIDI clip and edits the same note/event data persisted in `.lemmings` projects. Expressive lane edits are stored as MIDI event records so transport playback and later automation/export work can consume the same source of truth.

The Step Sequencer is project-level state with variable step counts, steps-per-beat timing, swing, per-lane MIDI notes, sample source paths, volume, pan, and hit arrays. Sequencer playback follows the project transport. **Print to Arrangement** creates a normal MIDI clip so the pattern can be edited, arranged, bounced, or automated outside the sequencer.

Sample-backed sequencer lanes use native one-shot AVAudioPlayerNode playback; lanes without samples trigger the current native/hosted/bridged instrument path through MIDI.

## Startup Branding and Splice MCP (buildfix254)

The visionOS target now bundles and shows the same MagmaVance pre-splash and LemmingsStudio splash assets used by the desktop app. The startup sequence is implemented as a visionOS-native SwiftUI/AVKit overlay instead of an AppKit-style splash window, so it works naturally in the main spatial workspace. Use **Replay Startup Branding** from the skin/theme menu to test it again during development.

Buildfix254 also adds the first visionOS Splice MCP parity seam. The **Splice MCP** window connects to the official remote MCP endpoint, keeps the returned MCP session id, and discovers advertised tools. This is a safe integration point for later Splice search, preview, authenticated download, Fetch-on-Drop, and Step Sequencer sample-assignment work. It does not scrape Splice or bypass authentication.

## Spatial Editing and Agentic MLX Lab (buildfix253)

Buildfix253 adds a persistent spatial scene graph for the visionOS port. The new **Spatial Editor** window exposes transform editing for DAW surfaces such as Arrangement, Mixer, Plug-in Rack, and Agent Panel. Each surface has position, rotation, scale, visibility, snapping, reset, duplicate/delete, and local undo/redo support.

The existing volumetric Spatial Control Deck remains available as the quick transport/zoom/snap surface. The Spatial Editor is the heavier scene-graph editor that will later drive real volumetric object placement, patch cables, floating plug-in controls, and workspace presets.

Buildfix253 also introduces the **Agentic MLX Lab**. This is intentionally a local-first tool-call seam rather than a finished model runtime. It records the target multimodal MLX model family, extracts project context, produces proposed tool calls, and requires explicit confirmation before applying safe preview actions. The model should propose operations; LemmingsStudio remains responsible for validating and executing them.


## buildfix256 — Gojira Compatibility Lab

This visionOS build now includes a sideload/dev-mode-only **Compatibility Lab** for local plugin compatibility research. It adds dry-run planning and classification seams for native AUv3, Integrated Mac Host Mode, experimental macOS `.component` probes, Wine ARM64, and Wine + FEX x64 experiments.

The lab is intentionally isolated from stable playback paths. Native AUv3 remains the preferred path, Integrated Mac Host Mode remains the reliable desktop-plugin path, and Wine/FEX/macOS-component loading stays behind the experimental Gojira surface until metadata scanners and runtime adapters are ready.

Next parity work: implement metadata-only component/VST3 scanners, define the shared plugin backend protocol for parameters/editor/audio/state, complete Integrated Mac Host Mode desktop-plugin parity, then use Wine ARM64 and FEX experiments as opt-in sideload research.


## Buildfix263 website release packaging

The public version remains **visionOS v1.0**, but distribution is split into two artifacts:

```bash
cd Ports/visionOS
./build-visionos.sh package-simulator
./build-visionos.sh ipa
```

Outputs are written to `Ports/visionOS/dist/` by default:

- `LemmingsStudio-visionOS-v1.0-Simulator.zip` — Release simulator `.app` bundle for Xcode/Simulator testers.
- `LemmingsStudio-visionOS-v1.0.ipa` — resignable sideload package for real Vision Pro hardware.

The public IPA packaging path does not require the release builder to provide an Apple distribution or development signing identity. It builds the Release device app with code signing disabled, wraps it as `Payload/LemmingsStudio.app`, removes stale app-level signature/provisioning metadata, and produces a resignable IPA. End users must sign or re-sign the IPA with their own Apple identity and provisioning workflow before installing it on Vision Pro. The separate `archive` mode remains available for developer-owned debugging/archive workflows.


## buildfix269 — Local MLX Runtime

The visionOS target now links the official MLX Swift LM 3.x package stack through XcodeGen and can load selected Hugging Face MLX VLM repositories locally. The MLX Runtime window sends Semantic Project Graph and Living Project Memory context to the model and can attach the latest streamed Mac Host Mode plug-in editor frame as image input. Tool plans are filtered against lane-specific allow-lists and require explicit confirmation before LemmingsStudio executes supported DAW actions. Load and generation work are cancellable, and the model container can be explicitly unloaded to release memory pressure.


## buildfix270 — Wine ARM64 bring-up

The Compatibility Lab now includes a staged Wine ARM64 bring-up pipeline for sideload/dev-mode research. It validates runtime layout and architecture, prepares a writable prefix, captures loader and DLL diagnostics, probes mmap/RW→RX memory transitions, runs an ARM64 Windows probe harness with timeouts and captured logs, enumerates VST3 candidates, and exposes focused DSP-transport and offscreen-editor bridge experiments. See `WINE_ARM64_STAGING.md` and `PATCHNOTES_buildfix270.md`.


## MLX Swift package plugin validation

The scripted visionOS builds pass `-skipPackagePluginValidation` by default because the pinned MLX Swift dependency exposes a transitive `CudaBuild` build-tool plugin that Xcode validates before compilation. This is scoped to `build-visionos.sh`; set `VISION_SKIP_PACKAGE_PLUGIN_VALIDATION=0` to restore normal validation behavior.

## Full-fat offline MLX model bundle (buildfix284)

visionOS builds now default to a full offline MLX payload. The first build downloads the curated model set into:

`~/Library/Caches/LemmingsStudio/visionOS-Models`

The cache is reused across subsequent source trees/buildfixes. The app bundle receives a `Models/` directory containing all four curated VLMs. Runtime loading prefers those bundled directories before any network-backed model resolution.

Profiles:

```bash
# minimal VLM bundle (default; full is explicit opt-in)
VISION_MODEL_BUNDLE_PROFILE=full ./build-visionos.sh simulator

# Qwen 3B + 7B only
VISION_MODEL_BUNDLE_PROFILE=default ./build-visionos.sh simulator

# Qwen 3B only
VISION_MODEL_BUNDLE_PROFILE=minimal ./build-visionos.sh simulator

# thin developer build
VISION_MODEL_BUNDLE_PROFILE=none ./build-visionos.sh simulator
```

The full profile is intentionally very large and may require well over 20 GB of free space for the model cache plus another comparable amount for the built app/package staging area.

## buildfix305 hybrid spatial automation

The **Spatial Automation Stage** adds a visionOS-only expressive performance layer on top of the existing automation lanes. Sway/Pulse use a two-dimensional performance field, while Glide, Press, Sculpt, and Strike provide additional expressive inputs. Any automation lane can map one of these gesture dimensions, constrain its normalized range, and invert the mapping. Recording still obeys Arm plus Read/Write/Touch/Latch, and the captured result is stored as normal beat/value points for exact editing and deterministic export.

## buildfix308 spatial performance additions

The floating MIDI keyboard now uses multi-event spatial input for simultaneous chord performance and glissando/stroking across keys. The volume is larger, the keyboard exposes the stock instrument selector, and the stock bank includes Oscillatron, LemmingBass, Glass Lemming, Cloud Pad, and Pluck Nest.

A new Sample Browser workspace imports audio through the system Files picker, caches it locally for reliable playback, previews it, and inserts it into Arrangement or the Step Sequencer. The browser model is provider-neutral for future remote-provider adapters.

## buildfix309: Xcode testing and release packaging

### Open and run in Xcode

From this directory:

```bash
export DEVELOPER_DIR="/Volumes/Zweidrive/Applications/Xcode-beta.app/Contents/Developer"
./open-in-xcode.sh
```

The helper prepares the default `minimal` model cache, generates `LemmingsStudioVision.xcodeproj`, and opens it. In Xcode select an Apple Vision Pro simulator and press `Command-R`. The generated target has a post-build phase that stages the selected model profile into the built app bundle before launch.

Override the profile when required:

```bash
VISION_MODEL_BUNDLE_PROFILE=none ./open-in-xcode.sh
VISION_MODEL_BUNDLE_PROFILE=full ./open-in-xcode.sh
```

### Release artifacts

Simulator ZIP:

```bash
./build-visionos.sh package-simulator
```

Unsigned/resignable device IPA:

```bash
./build-visionos.sh ipa
```

The IPA intentionally contains no `_CodeSignature` directory and no `embedded.mobileprovision`. Recipients sign it with their own Apple Developer identity and provisioning profile before installation.
