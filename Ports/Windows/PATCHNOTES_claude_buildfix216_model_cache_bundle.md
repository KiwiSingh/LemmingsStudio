# Buildfix216 — Windows Demucs model-cache bundling

This fixes an important packaging gap in buildfix215:

- `-BundleModels` / `-PreloadModels` no longer only warms the builder machine's user cache.
- The Windows build now stages a portable `model-cache/torch` directory inside the publish folder.
- The Inno installer includes that cache because it already recursively copies the publish folder.
- `scripts/setup-backend.ps1` seeds the installed user's PyTorch/Demucs cache from the bundled cache before first use.
- The build can preload multiple Demucs models through `-ModelNames`.

Default bundled models when `-BundleModels` is used:

- `htdemucs`
- `htdemucs_ft`
- `htdemucs_6s`

Examples:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-arm64 -BundleModels
```

Smaller installer:

```powershell
./build-windows.ps1 -Backend cpu -Runtime win-arm64 -BundleModels -ModelNames htdemucs
```

Notes:

- This bundles Demucs/PyTorch cache weights, not arbitrary user-imported RVC `.pth` voices.
- RVC starter entries are catalogue/profile slots; users still need consent-cleared imported RVC models unless real built-in voice weights are supplied separately.
