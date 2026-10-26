# LemmingsStudio Windows Python rewrite

This experimental implementation lives only on `rewrite/python-windows`.
The branch starts at main commit `4a2c0cf1b137e21152fa9d8cf9844f2c5ec777fc`.
The Swift macOS app, existing Windows port, their build scripts and original project
formats remain intact. This is not a feature-complete replacement or a release.

## Run in an isolated environment

The product target is Windows 11 x64 with Python 3.13. macOS may be used for
source-level development checks; the macOS product remains the existing Swift app:

```text
python -m venv .venv
```

Activate with `.venv\Scripts\Activate.ps1` on Windows, then:

```text
python -m pip install -e "./PythonStudio[test]"
python -m lemmings_studio
python -m pytest PythonStudio/tests -q
```

The package uses PySide6 Essentials for the interface, NumPy for block processing,
SoundFile/libsndfile for media and SoundDevice/PortAudio for output. The Windows preview bundle includes Python and native libraries. It can be
built and smoke-tested without replacing the existing Windows installation. Dependencies are
pinned; full platform wheel hashes and release licensing review remain pending.

## Working migration slice

- A Windows workspace with dockable Library and Inspector, transport,
  arrangement, piano roll, step sequencer and mixer. Toolbars have overflow menus;
  docks can be hidden from View on small displays. Initial size follows the screen.
- Add audio/MIDI tracks, import audio, create and move clips, edit start/length,
  duplicate/delete clips, draw/move/delete MIDI notes, toggle sequencer steps,
  change instrument, gain, pan, mute and solo, with transactional undo/redo.
- Save/open `.lemmingspy` projects with stable IDs, unknown-field retention,
  verification, atomic replacement and a backup. Failed edits leave the prior
  document intact. Unsaved changes require explicit discard on close/open/new.
- Play and export through the same block renderer. Stereo/mono audio resampling,
  five original basic synth/percussion voices, mute/solo and pan are included.
  Audio devices, decoding and exports run outside the Qt thread. Export cancellation
  preserves an existing destination. This is not low-latency certified.

Start with two empty tracks. Add a MIDI clip from Track, then draw notes by
double-clicking the Piano Roll. Double-click an existing arrangement clip to open
its notes. Drag clips or notes to move them; edit clip length in Inspector.
Choose `drums` as the instrument for the sequencer's synthesized percussion.
Play requires an available stereo output device; exports and project editing do not.

## Preservation and limitations

Only the new `.lemmingspy` format is writable. Older macOS/Windows projects are
not silently imported or overwritten. Their full migration, including embedded
macOS audio, AU state, routing, warp and devices, is a separate compatibility gate.
Do not assume sonic or feature parity with the Swift build. Source retention is
not equivalent to playback compatibility.

This slice does not yet implement recording, MIDI hardware, full session launching,
plugin hosting, the macOS device catalog/effect chains, automation, sends/returns,
warp, freeze, AI providers, stem separation, Splice, VoxGarden integration or the
planned sampled guitar/drum products. No sounds, models or third-party presets are
bundled. See `Docs/PythonRewrite/PARITY.md` for the migration register.

Playback uses blocking PortAudio writes on a worker thread, with a conservative
2048-frame buffer; there is no Python callback on PortAudio's real-time thread.
NumPy performs array processing in native code, but this is not a guarantee of
real-time scheduling. Decoding currently preloads files of up to ten minutes;
long-file streaming and performance certification remain gates. Mixing includes
output clipping protection. Basic oscillators are not the Mac instrument catalog.

No installer, file association, shared preset location, model folder or production
application is replaced by running this branch. Keep all existing builds until
feature, project, audio, installer and real-hardware validation passes.

## Windows preview bundle

The `Windows Python rewrite` Actions workflow runs the Windows checks, builds a
self-contained x64 folder with PyInstaller 6.22.3, then executes its isolated
`--self-test-report` mode. That test loads PortAudio and libsndfile, checks the
800x600 workspace, edits/undo/redo, project save/reopen and aligned stereo export.
It does not open hardware devices or establish full macOS feature parity.

To reproduce on Windows after installing the development dependencies:

```powershell
python -m pip install pyinstaller==6.22.3
./PythonStudio/build-windows.ps1 -OutputRoot D:/LemmingsStudio/Artifacts/PythonPreview
```

Keep the entire `LemmingsStudio Windows Preview` folder together. Run its `.exe`;
no external Python installation is needed. The folder is a portable internal
preview, not an installer or a signed public release. The CI artifact also includes
matching source, version/commit information and development license metadata.

## Storage during development

On this Mac the active repository, environment, logs, caches, temporary files and
artifacts live under `/Volumes/Zweidrive/LemmingsStudio`. Source
`/Volumes/Zweidrive/LemmingsStudio/environment.zsh` before local builds and tests.
The environment directory is linked to the existing virtual environment on the
same drive. This is a Windows product; running source checks on macOS does not
replace or rebuild the Swift application.

## Original startup and launch diagnostics

The Windows development build now presents the original MagmaVance video, then
LemmingsStudio artwork and the 1.55-second splash, with the original opening WAV.
It uses custom Qt Quick presentation and CPU video frames so software rendering
can work in a VM. Audio-library imports are deferred until after the first startup
frame; model loading, plugin scanning and network jobs are not part of this path.
The workspace remains the earlier development UI; this is not full visual parity.

The build stages eleven byte-identical Mac media assets from their pinned source
checksums. It bundles Qt Multimedia and tests an actual Windows desktop launch,
video decoding, opening-WAV decoding and workspace handover. The check does not
play sound or certify hardware audio latency. Its captures and phase timings are
included in the validation artifact.

Use `--software-rendering` if the graphics driver cannot initialize Qt Quick.
A reported scene-graph initialization failure retries once with software rendering.
`--startup-check-report <file.json>` exercises the startup and workspace without
playing the opening sound. `--self-test-report` remains the separate editing/audio
smoke check. The installer also verifies the installed startup presentation.

Logs begin before Qt/audio imports. Windows stores them in
`%LOCALAPPDATA%\LemmingsStudio\Diagnostics`; development uses the external checkout
or `LEMMINGS_DIAGNOSTICS_DIR`. QML caches follow that explicit external location.
Failed startup reports a log path, and the monitored initialization phase has a
30-second timeout. A native crash can leave a fault log; a graphics driver that
aborts the process before Qt reports an error may still require the explicit
software-rendering option. Native-hardware cold/warm launch targets remain unverified.
