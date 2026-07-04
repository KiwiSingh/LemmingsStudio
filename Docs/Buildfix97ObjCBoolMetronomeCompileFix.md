# Buildfix97 — ObjCBool metronome compile fix

Buildfix96 failed under Xcode 27 because the AVAudioSourceNode `isSilence` pointer is an `ObjCBool` pointer, and the metronome source node assigned a computed Swift `Bool` expression directly to `isSilence.pointee`.

This buildfix wraps the computed expression with `ObjCBool(...)`:

```swift
isSilence.pointee = ObjCBool(!self.metronomeEnabled || !self.transport.isPlaying)
```

No Splice MCP/download/preview integration files were touched.
