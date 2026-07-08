# LemmingsStudio buildfix287

## visionOS build-script compatibility hotfix

- Fixed `build-visionos.sh` failing under macOS Bash with `set -u` when both package/macro validation bypasses are disabled.
- Empty `package_validation_flags` arrays are now expanded with a nounset-safe Bash compatibility idiom.
- Applied the fix consistently to simulator, archive, simulator packaging, and resignable IPA build paths.
- Verified shell syntax and all four validation-flag combinations for argument assembly.

Public version numbers are unchanged:
- macOS 2.0
- Windows 2.0
- visionOS 1.0
