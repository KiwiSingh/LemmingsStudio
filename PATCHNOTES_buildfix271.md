# LemmingsStudio buildfix271 — Final Parity Audit & Launch Hardening

Public versions remain macOS v2.0, Windows v2.0, and visionOS v1.0.

## Added

- repository-wide release/version audit script (`release-audit.sh`)
- macOS release wrapper with bundle-version checks and SHA-256 manifest (`release-macos.sh`)
- visionOS Simulator/hardware release wrapper with deterministic artifact verification (`Ports/visionOS/release-visionos.sh`)
- Windows release verification wrapper with version gates, existing build pipeline invocation, sanity checks, and SHA-256 manifest (`Ports/Windows/release-windows.ps1`)
- launch parity matrix separating implemented source paths, hardware validation requirements, release blockers, and experimental claims
- detailed launch test protocol for macOS, Windows, visionOS Simulator, and Apple Vision Pro hardware
- consolidated release-readiness document and public artifact naming rules

## Hardening philosophy

buildfix271 does not claim that a Linux CI container can certify Xcode signing, Vision Pro thermals, Metal inference, Apple provisioning, Windows installer execution, third-party plugin GUI behavior, or authenticated Splice service behavior. It adds deterministic local gates and platform-native verification scripts, and clearly identifies the remaining hardware/toolchain checks.

## Release versions

- macOS v2.0 (`2.0` / `2.0.0`)
- Windows v2.0 (`2.0.0` / `2.0.0.0`)
- visionOS v1.0 (`1.0` / `1.0.0`)
- Linux remains source-only on GitHub
