# LemmingsStudio buildfix270 — Wine ARM64 Bring-Up

Public versions remain unchanged:

- macOS v2.0
- Windows v2.0
- visionOS v1.0

## What landed

### Staged Wine ARM64 runtime bring-up pipeline

The visionOS Gojira Compatibility Lab now runs a phase-gated local bring-up sequence for sideload/dev-mode Wine ARM64 research:

1. runtime-layout validation
2. arm64 Mach-O runtime validation
3. PE/COFF arm64 plug-in target validation
4. writable Wine-prefix preparation
5. Wine loader smoke test and captured loader logs
6. DLL search-root diagnostics and `WINEDLLPATH` reporting
7. anonymous `mmap` + RW→RX→RW memory-permission diagnostic without executing generated code
8. Windows ARM64 `vsthost-probe.exe --self-test --json`
9. VST3 enumeration
10. DSP callback transport experiment
11. offscreen editor surface/input bridge experiment

The full bring-up stops at the first blocked phase so later failures do not hide the root cause.

### Architecture gates

The Wine ARM64 lane now rejects architecture mismatches before process execution. It requires:

- an arm64 Mach-O Wine runtime executable
- a PE/COFF arm64 Windows target

x86-64 targets remain on the separate Wine + FEX research lane.

### Captured child-process diagnostics

Probe launches now capture stdout and stderr into report logs. Each process has a timeout. Hung children are terminated using SIGTERM and then SIGKILL if required.

Reports store:

- phase
- pass/block state
- headline
- detail/log output
- command line
- exit code
- runtime root
- aggregate pass/fail count

### Focused experiment controls

The Compatibility Lab now exposes separate actions for:

- full ARM64 bring-up
- VST3 enumeration
- DSP transport probe
- editor bridge probe

Focused probes can be repeated without rerunning the whole pipeline after the runtime is healthy.

### DSP transport experiment contract

The probe host is invoked with a narrow experimental contract:

- 48 kHz
- 256-frame blocks
- 128 test blocks
- `shared-ring-v1` transport identifier

This does not claim completed production DSP bridging; it creates a concrete executable boundary for the Windows probe host and future native audio-ring implementation.

### Editor bridge experiment contract

The editor probe path requests:

- offscreen editor mode
- `bgra8-shared-buffer` surface contract
- `lemmings-pointer-v1` input protocol
- bounded frame count

This is intentionally a probe contract, not a claim that arbitrary Windows plug-in editors already render correctly on visionOS.

### Runtime staging guide

`Ports/visionOS/WINE_ARM64_STAGING.md` documents the expected sideload staging tree, runtime executable names, DLL roots, prefix location, and probe harness location.

The build does not bundle Wine binaries or third-party plug-ins.

## Validation performed in the available environment

- Whole visionOS Swift tree parser validation passed.
- `build-visionos.sh` shell syntax validation passed.
- Public version matrix remains macOS/Windows v2.0 and visionOS v1.0.
- Final ZIP integrity test passed.

## Still requires macOS/Xcode and Vision Pro hardware

- visionOS SDK type checking
- entitlement/process-execution behavior on a sideloaded build
- actual staged Wine ARM64 runtime execution
- `wine --version` loader behavior on-device
- PE ARM64 probe execution
- DLL loading behavior
- real VST3 module enumeration
- realtime DSP callback transport
- editor surface transfer and pointer input
- long-running crash isolation and thermal profiling

## Next for full macOS parity

buildfix271 is the final parity and launch-hardening pass:

1. macOS ↔ visionOS feature-matrix audit
2. Xcode compile and package-resolution fixes
3. Vision Pro hardware validation
4. Mac Host Mode latency measurement
5. MLX model memory/thermal profiling
6. recording and automation stress tests
7. Splice authentication/download validation
8. project open/save compatibility audit
9. Simulator ZIP packaging
10. signed hardware IPA packaging
11. macOS v2.0 release package
12. Windows v2.0 installer verification
