# Buildfix162 — Stem Runner Logging Compile Fix

Scope: tiny compile fix for buildfix161's terminal/log-file stem diagnostics.

## Fix

`StemSplitter.runSeparationProcess(...)` logged the stem log path from an async closure using:

```swift
stemLogFileURL()
```

Because `stemLogFileURL` is a static helper on `StemSplitter`, Swift resolved that as an invalid instance member access inside the closure. The build failed with:

```text
static member 'stemLogFileURL' cannot be used on instance of type 'StemSplitter'
```

The call now uses the explicit static form:

```swift
Self.stemLogFileURL()
```

## Files changed

- `Sources/LemmingsStudio/Generative/StemSplitter.swift`
- `Docs/Buildfix162StemRunnerLoggingCompileFix.md`

## Untouched

Recording, code signing, Splice, Serum/Serum 2/plugin fixes, AU hosting, RVC/build.sh, Demucs packaging, export, mixer clipping, warp controls, metronome/count-in, and Finder import were not touched.
