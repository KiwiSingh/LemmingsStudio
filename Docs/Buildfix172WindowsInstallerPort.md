# Buildfix172 — Windows Installer Port Pass

## Scope

This buildfix adds a real Windows installer build path and beginner-friendly docs.

## Added / changed

- `Ports/Windows/src/LemmingsStudio.Windows/` — native .NET 8 WinForms Windows shell.
- `Ports/Windows/build-installer.ps1` — publishes the Windows app and builds an Inno Setup installer.
- `Ports/Windows/build-windows.ps1` — compatibility wrapper for the previous scaffold command.
- `Ports/Windows/scripts/setup-backend.ps1` — installs CPU/DirectML/CUDA backend dependencies into the user's LocalAppData.
- `Ports/Windows/scripts/test-stems.ps1` — stem backend smoke test helper.
- `Ports/Windows/scripts/detect-hardware.ps1` — Windows hardware recommendation helper.
- `Ports/Windows/installer/LemmingsStudio.iss` — Inno Setup installer recipe.
- `.github/workflows/windows-installer.yml` — manual GitHub Actions installer workflow.
- `Docs/WindowsBuildForNoobs.md` — full no-prior-knowledge build guide.
- `Docs/WindowsPortPlan.md` — updated Windows compatibility and port roadmap.

## Not touched

- macOS stem splitter logic/backend code/packaging
- recording
- code signing
- Splice
- Serum / Serum 2 / hosted plugin fixes
- AU hosting
- RVC/build.sh
- export
- mixer clipping
- warp controls
- metronome/count-in
- Finder import
- MIDI learn
- automation
- User Library scanning

## Notes

The Windows build is now installable and backend-testable, but it is not yet full DAW feature parity. The macOS app remains the reference implementation while Windows-native project/audio/arrangement/plugin layers are ported.
