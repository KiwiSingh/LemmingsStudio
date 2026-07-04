# Lemmings Studio — buildfix166 (Claude): Automation "Add Lane" actually adds lanes

## Why it did nothing
"Add Lane" is a `Menu` built from `nodes(track)`. That function only offered the instrument's
parameters when the engine had a **live** instrument node:
```swift
if let inst = app.engine.liveNode(track: track, nodeID: "instrument") { ... }
```
On a freshly added instrument track (or any time before playback instantiated the node), that
was nil and the track had no devices yet — so the menu had **zero items**. Clicking it opened
an empty menu, i.e. "absolutely nothing."

## Fix (`AutomationEditor.swift`)
- The instrument's automatable params now come from the live node **or**, as a fallback, a
  factory-built instrument (`engine.makeInstrument(for:) as? Automatable`) — so the menu is
  populated whether or not the engine has instantiated the track. (Hosted-AU instruments are
  cached by the engine, so this stays cheap.)
- Empty param lists are filtered out, and if a track genuinely has nothing to automate (e.g. a
  bare audio track), the menu now shows a clear **"No automatable parameters on this track"**
  item plus an "Add a device first…" shortcut to the Devices tab — feedback instead of silence.
- `nodes(track)` is now evaluated lazily inside the menu (only on open), not on every render,
  so it doesn't allocate an instrument each frame.

Picking a parameter calls `track.lane(nodeID:paramID:)`, which appends to the `@Observable`
Track's `automationLanes` — so the new lane (with its breakpoint canvas) appears immediately.

## Build note
Authored without the Swift toolchain — expect minor Xcode fixups. Brace-balanced.
