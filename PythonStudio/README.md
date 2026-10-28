# LemmingsStudio Windows parity branch

Development branch: `rewrite/python-windows`, based on Mac reference
`4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`. Main and the Swift macOS product
are unchanged by this workspace phase. This is an experimental build, not an
accepted feature-complete Windows replacement.

## Normal application

The branded startup now opens a custom Qt Quick workspace, backed directly by
`.lemmingsproject` v3. It reads existing v1/v2 documents, preserves opaque/unknown
state and uses atomic saves/backups. The old Qt Widgets/`.lemmingspy` preview
remains only as a legacy regression harness; it is not the normal application.

Seven pages are available: Session, Arrangement, Piano Roll, Step Sequencer,
Devices, Automation and Mixer. The shell includes resizable panes, lower detail
deck, browser, seven right-dock destinations, inspector, menus and shortcuts.
Small screens use accessible browser/inspector drawers and scrolling transport.
All eleven original theme palettes and 26 scale definitions come from actual
Swift reference exports, alongside the original 94-device parameter registry.

Implemented edits include audio import, MIDI clips, moving/resizing/splitting/
duplicating/deleting clips, drawing/moving/resizing/quantizing/deleting notes,
velocity, simultaneous drum steps, single-undo pattern printing without double
triggering, track duplication/groups, device parameters/chains, tempo and device
automation points, mixer/return/send state and undo/redo. Preserved third-party
plugin slots show their identity and unavailable state.

The native offline engine contains the ten actual Mac drum voices, original kits,
24-slot kit allocation/retrigger behavior and the original master limiter. Normal
playback and export use this engine for drum tracks and embedded unwarped audio.
Unsupported audible instruments, effects, routing, automation, swing, freeze,
layer processing or warp stop rendering with an explanation; they are never
silently replaced by generic oscillators. Mixer editing does not establish that
the routing graph is complete. PortAudio remains development output; this is
not the planned real-time WASAPI/ASIO graph.

## Remaining acceptance gates

See [the workspace ledger](../Docs/Parity/WORKSPACE_UI.md). Advanced editing,
per-device preset strips, external plugin replacement/hosting, live meters,
recording, monitoring, full stock DSP, automation/routing playback, service
adapters and VoxGarden integration remain unfinished. AI/Splice/voice actions
are explicitly unavailable. Exact packaged-Mac visual comparison, interaction
recordings, hardware and accessibility acceptance are still required. Loading
seven pages alone does not establish full UI parity.

The original VoxGarden repository is untouched. The app-bound integration lives
in its separate repository; this package supplies no external-DAW installer.

## Run and validate

Target Windows 11 x64 / Python 3.13. Install into an isolated environment on the
project drive, with pinned dependencies:

```text
python -m pip install -c PythonStudio/requirements-lock.txt -e "./PythonStudio[test]"
python -m lemmings_studio
python -m pytest PythonStudio/tests -q
```

Build `PythonStudio/native` with CMake into an external directory; set
`LEMMINGS_NATIVE_LIBRARY` to the resulting library for source playback. The Windows
build script builds/bundles the DLL and its static C++ runtime automatically:

```powershell
./PythonStudio/build-windows.ps1 -OutputRoot D:/LemmingsStudio/Artifacts/Workspace
```

On this Mac, source `/Volumes/Zweidrive/LemmingsStudio/environment.zsh` first.
All source, environments, models, caches, temporary files, logs and artifacts stay
on Zweidrive. Running source checks does not replace the Swift application.

`Tests/ProjectCompatibility/run.sh` exports real Swift projects, palettes,
parameters, scales, kits, drum audio and limiter audio. Set `LEMMINGS_TEST_OUTPUT`
to an external directory. The parity workflow compares Windows native output
against those references and tests a Swift → Python → Swift document round trip.

`--startup-check-report <file.json>` uses the actual desktop backend, suppresses
sound playback, decodes the original media, exercises shared-document edits,
checks all pages at 1600×900 and 1024×768, captures all eleven themes, and renders
the native drum/limiter path. Evidence is included in CI validation artifacts.
It does not certify real audio hardware. `--self-test-report` retains the older
Qt Widgets regression checks separately.

## Distribution and diagnostics

The conventional per-user setup wizard bundles Python, Qt, native audio and
original startup assets. It installs separately, without changing file
associations or external DAW settings. Keep the whole portable folder together
when using that artifact. Install/reinstall/uninstall checks preserve projects.
This is an unsigned internal preview; signing, clean-machine hardware validation
and final dependency/content licensing review remain release gates.

Original MagmaVance videos, splash artwork and opening WAV are staged by pinned
checksums. Media/audio initialization follows the first visible startup frame.
Use `--software-rendering` for VM graphics. Logs begin before imports and report
startup failures instead of leaving an invisible process. Windows diagnostics
use `%LOCALAPPDATA%\LemmingsStudio\Diagnostics` or `LEMMINGS_DIAGNOSTICS_DIR`;
development redirects logs and QML caches to Zweidrive.
