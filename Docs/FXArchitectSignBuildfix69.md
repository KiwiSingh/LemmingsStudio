# FX Architect / Drum Buss Sign Buildfix 69

Fixes a Swift toolchain compatibility issue where `Float.signum()` was not accepted by the macOS/Xcode beta compiler.

The drum bus transient snap now uses the local `fsign(_:)` helper instead, preserving the same positive/negative/zero behavior without relying on that unavailable member.
