# Buildfix225 — v1.1 metadata and MagmaVance bundle identifier

This buildfix updates branding/version metadata after the startup splash and copyright pass.

## macOS
- `build.sh` now uses `BUNDLE_ID="com.magmavance.LemmingsStudio"`.
- The generated `Info.plist` now reports:
  - `CFBundleShortVersionString = 1.1`
  - `CFBundleVersion = 1.1.0`
- Added optional `APP_VERSION_SHORT` and `APP_BUILD_VERSION` environment overrides for future release packaging.

## Windows
- `build-windows.ps1` and `build-installer.ps1` default to version `1.1.0`.
- The Windows `.csproj` now reports assembly/file/informational version `1.1.0`.
- The Inno installer metadata now reports `AppVersion=1.1.0` and `VersionInfoVersion=1.1.0.0`.
- Publisher/company metadata is now `MagmaVance LLC`.

## Docs
- Updated bundle-ID references from `com.kiwisingh.LemmingsStudio` to `com.magmavance.LemmingsStudio`.
