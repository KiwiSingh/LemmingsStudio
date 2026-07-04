# Buildfix 202 – AU Effect Host Compile Fix

## Problem
Buildfix201 added a live AU insert host for third-party plug-in automation, but the `AURenderPullInputBlock` treated its `outData` argument as optional:

```swift
guard let outData else { return noErr }
```

On the current macOS SDK/Xcode beta signature, `outData` is already a non-optional `UnsafeMutablePointer<AudioBufferList>`, so Swift rejected the conditional binding.

## Fix
Removed the optional binding and passed the non-optional pointer directly into `UnsafeMutableAudioBufferListPointer`.

This keeps the AU effect host path intact while restoring compilation.

## Files Changed
- `Sources/LemmingsStudio/Plugins/AUHosting.swift`
