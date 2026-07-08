# buildfix305 hotfix 1

- Fixes Xcode 27 / visionOS 27 compiler resolution of AVAudioPlayerNode.scheduleBuffer in VisionNativeExport.swift by explicitly selecting the synchronous completion-handler overload.
- Avoids awaiting buffer completion before AVAudioEngine startup, preserving offline-render graph sequencing.
- Cleans the Swift 6 implicit-strong-capture warning in native export progress handling.
