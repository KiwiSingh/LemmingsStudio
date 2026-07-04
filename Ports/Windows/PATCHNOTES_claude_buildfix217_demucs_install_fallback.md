# Buildfix 217 — Windows Demucs install fallback

Fixes Windows backend setup failures where `pip install demucs` tries to build the PyPI source distribution and crashes because `requirements_minimal.txt` is missing from the temporary sdist extraction.

Changes:

- Removed `demucs` from the bulk dependency install line so a Demucs failure does not poison the entire core dependency step.
- Added a dedicated `Install-DemucsPackage` helper in `scripts/setup-backend.ps1`.
- The helper first tries normal PyPI with `--prefer-binary`.
- If PyPI fails, it retries from the official GitHub source archive ZIP instead of requiring `git.exe` on a fresh Windows install.
- Existing partially-created backend venvs can be repaired by rerunning backend setup or rerunning the Windows build command.

Retry:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-arm64 -BundleModels
```

If you are only repairing an installed backend:

```powershell
.\scripts\setup-backend.ps1 -Backend cpu -PreloadModels
```
