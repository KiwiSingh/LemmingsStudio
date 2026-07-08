# Wine ARM64 staging layout — buildfix270

The shipping visionOS build does **not** bundle Wine or third-party plug-ins. Gojira Compatibility Lab expects a sideload/dev-mode staging tree inside the app's Documents container:

```
Documents/LemmingsStudio/Runtimes/wine-visionos/
├── bin/
│   ├── wine64-arm64   # preferred name
│   └── wineserver     # optional but expected by many Wine builds
├── lib/
│   └── wine/
│       └── aarch64-windows/
├── prefix/
│   └── drive_c/
│       └── windows/
│           └── system32/
└── vsthost-probe.exe  # Windows ARM64 probe harness
```

The first supported experiment lane is **PE/COFF ARM64**. x86-64 Windows binaries remain on the separate Wine+FEX research path and are rejected by the ARM64 bring-up gate.

Buildfix270 performs:

1. Runtime layout validation.
2. Mach-O arm64 runtime + PE/COFF arm64 candidate validation.
3. Prefix writability checks.
4. `wine --version` loader smoke test.
5. DLL search-root diagnostics.
6. anonymous `mmap` and RW→RX→RW permission-transition diagnostic without executing generated code.
7. `vsthost-probe.exe --self-test --json`.
8. VST3 enumeration.
9. DSP block-transport experiment using the `shared-ring-v1` probe contract.
10. Offscreen editor experiment using `bgra8-shared-buffer` and `lemmings-pointer-v1` contracts.

Every child process captures stdout/stderr, has a timeout, and is terminated if it hangs. This is experimental sideload-only research, not universal plug-in compatibility.
