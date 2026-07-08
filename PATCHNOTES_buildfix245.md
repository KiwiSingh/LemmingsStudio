# LemmingsStudio buildfix245 — Windows release hardening

This pass focuses on release-day failure prevention and recoverability.

## Autosave and crash recovery

- Added `ProjectRecoveryService`.
- Dirty projects autosave every 60 seconds to `%LOCALAPPDATA%\MagmaVance\LemmingsStudio\Autosaves`.
- Recovery files use atomic project writes and sidecar metadata.
- On startup, the newest recovery candidate is offered to the user.
- Normal project saves remove the matching recovery copy.
- New/Open/Exit prompt before discarding unsaved work.

## Atomic project saves

- `ProjectIO.SaveAtomic` writes to a temporary file, deserializes it to verify validity, then replaces the target.
- Existing project files receive `.bak` backups during replacement.
- This reduces the chance of a truncated project after power loss or interrupted writes.

## Missing media and plug-in handling

- Opening a project performs a health audit.
- Missing audio and sequencer sample files are reported.
- Missing VST3 plug-ins are bypassed and marked instead of crashing project load.
- Added File → Relink Missing Media… with recursive filename-based relinking.
- Project-health results are included in parity diagnostics and diagnostics bundles.

## Native VST3 host crash recovery

- Unexpected helper exit increments a crash counter and emits a crash event.
- Pending IPC requests are failed cleanly.
- Hydrated-slot state is cleared so plug-ins can be reloaded after restart.
- Added Tools → Restart Native VST3 Host.
- Crash count is included in diagnostics.

## Diagnostics bundle export

- Added Tools → Export Diagnostics Bundle…
- Produces a ZIP under `%LOCALAPPDATA%\MagmaVance\LemmingsStudio\Diagnostics` containing:
  - system/runtime summary,
  - project health report,
  - recent in-app log lines,
  - Windows build manifest when present,
  - native-host presence marker.

## First-run folders and path sanity

- Added centralized `AppPaths` creation for autosaves, logs, diagnostics, projects, recordings, renders and Splice cache.
- Added startup writable-folder checks.
- Added Unicode and long-path filesystem smoke test using multilingual path names.

## Build/release sanity gate

- Added `scripts/test-release-sanity.ps1`.
- `build-installer.ps1` now runs it after publish and before installer packaging.
- Verifies required publish artifacts.
- Honors `-RequireNativeVst3Host`.
- Tests Unicode/long-path filesystem round trips.

## Validation limitation

The source was structurally inspected in the Linux workspace, but the Windows .NET/Visual Studio toolchain is not installed there. Final compilation and runtime validation must be performed on Windows.
