# Buildfix171 — DMG Packager, Installer Helper, FAQ, Windows Port Scaffold

## Scope

Adds release packaging and planning assets without touching audio/stem/recording/export logic.

## Added

- `create-dmg`
  - Packages an existing `LemmingsStudio.app` into a compressed DMG using `hdiutil`.
  - Stages the app, installer helper, and FAQ/readme files.

- `Scripts/install-lemmingsstudio.command`
  - Lets the user install to `/Applications` or an external drive's `Applications` folder.
  - Creates the external `Applications` folder when missing.
  - Removes quarantine and adds a local Gatekeeper label using sudo.
  - Prompts for a password only when macOS requires it.
  - Does not alter build-time code-signing logic.

- `Docs/YouTubeBetaFAQ.md`
  - Beta FAQ for the launch video.
  - Covers MacBook Neo, disk space, macOS version, Gatekeeper, external SSD installs, Windows/Linux status.

- `Docs/WindowsPortPlan.md`
  - Honest Windows port plan.
  - Covers Parallels/local Mac, GitHub Actions, private repo builds, CUDA/DirectML/OpenVINO/NPU compatibility strategy.

- `Ports/Windows/build-windows.ps1`
  - Initial Windows backend bootstrap script for CPU/DirectML/CUDA dependency environments.

- `.github/workflows/windows-port.yml`
  - Manual GitHub Actions workflow scaffold for Windows backend bootstrap tests.

## Not touched

Stem splitter logic, stem backend code, stem packaging, recording, code signing build logic, Splice, Serum/Serum 2/plugin fixes, AU hosting, RVC/build.sh, export, mixer clipping, warp controls, metronome/count-in, Finder import, MIDI learn, automation, and User Library scanning.
