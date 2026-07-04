# Buildfix 177 — Drag/drop plug-in editor MainActor compile fix

## Problem

Buildfix 176 fixed Serum 2 / AU instrument drag/drop by opening the newly inserted live plug-in editor automatically. On Swift 6 / Xcode beta builds, that introduced a compile-time actor isolation error:

```text
App.swift:3196:17: error: call to main actor-isolated instance method 'openPluginGUI' in a synchronous nonisolated context
```

`openPluginGUI(_:)` is correctly `@MainActor` because it opens AppKit/CoreAudioKit UI. The drag/drop parser can be entered from nonisolated SwiftUI/AppKit callback contexts, so directly calling the editor opener there violates actor isolation.

## Fix

The plug-in drag/drop path now explicitly hops to the main actor before opening the editor:

```swift
Task { @MainActor [weak self] in
    self?.openPluginGUI(slot)
}
```

This keeps the Buildfix 176 behavior — plug-ins inserted by drag/drop still open automatically — while satisfying Swift's actor isolation rules.

## Files changed

- `Sources/LemmingsStudio/App/App.swift`

## Expected behavior

- Dragging Serum 2 or another discovered plug-in onto a track still inserts it.
- The editor window opens via the live engine path.
- Swift 6 / Xcode beta no longer fails with `ActorIsolatedCall` at the drag/drop site.
