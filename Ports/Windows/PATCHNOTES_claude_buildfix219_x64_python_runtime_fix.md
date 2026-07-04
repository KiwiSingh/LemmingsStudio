# Buildfix219 — Windows x64 backend now uses x64 Python

Fixes a Parallels/Windows-on-ARM packaging bug where `./build-windows.ps1 -Runtime win-x64 -BundleModels` still ran backend setup with the machine default native ARM64 Python. That caused Demucs to be disabled or to hit ARM64-only package gaps even though the app runtime was x64.

## Changes

- `scripts/setup-backend.ps1` now accepts `-Runtime win-x64|win-arm64|auto`.
- For `win-x64`, setup resolves an x64 Python first via the `py` launcher/common install paths.
- If no x64 Python is available, setup installs a user-local Python 3.11 x64 under `%LOCALAPPDATA%\LemmingsStudio\Python\Python311-x64`.
- Existing backend venvs are checked for architecture mismatch and recreated when needed.
- Installer shortcuts and post-install backend setup now pass `-Runtime {#Runtime}`.
- Build-time Demucs model preload now passes the selected runtime too.
- In-app “Install / Repair Backend” and stem split calls now pass the runtime from `windows-build-manifest.json`.

## Retry

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-x64 -BundleModels
```

If an old ARM64 CPU backend already exists, this build will detect it and recreate it as x64.
