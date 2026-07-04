# Buildfix132 — Theme Preview Background Compile Fix

## Problem
Buildfix131 used SwiftUI's `background(_:in:fillStyle:)` overload with a `ZStack` as the first argument in `ThemePreviewCard`.

On the user's Xcode/macOS beta toolchain, that overload expects a `ShapeStyle`, so the build failed with:

> `ZStack<TupleView<...>>` does not conform to `ShapeStyle`

## Fix
`ThemePreviewCard` now uses the view-builder `background { ... }` overload and clips the stacked gradients/panel color with `RoundedRectangle` manually.

This preserves the same Liquid Glass theme preview appearance without asking SwiftUI to treat a view tree as a shape style.

## Untouched
Splice MCP/download/preview, Sound Agent, Demucs/stems, AU hosting, Piano Roll, browser drag/drop, mic recording, monitor modes, mixer FX, and metronome/count-in were not touched.
