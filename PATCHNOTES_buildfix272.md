# LemmingsStudio buildfix272 — visionOS public sideload IPA hotfix

Public versions remain macOS v2.0, Windows v2.0, and visionOS v1.0.

## visionOS packaging correction

The public hardware IPA path no longer archives/exports a developer-signed IPA using the release builder's Apple identity. Instead it:

1. builds the Release visionOS device target with code signing disabled;
2. packages `LemmingsStudio.app` under `Payload/`;
3. removes stale app-level `_CodeSignature` and `embedded.mobileprovision` metadata;
4. creates `LemmingsStudio-visionOS-v1.0.ipa` as a resignable sideload artifact;
5. leaves signing/re-signing to the end user's Apple identity/provisioning workflow at install time.

The separate `archive` mode remains available for developer-owned debugging and local signing workflows.

## Release hardening updates

- release audit now verifies unsigned public IPA build flags and Payload packaging;
- visionOS release wrapper clearly labels the hardware artifact as resignable;
- launch test protocol now starts hardware testing with an end-user sign/re-sign step;
- readiness and parity docs no longer require release-builder signing credentials for the public IPA;
- Simulator ZIP behavior remains unchanged.
