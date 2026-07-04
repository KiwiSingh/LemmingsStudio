# Splice AppKit Results Isolation Buildfix 78

This build hardens Splice Sounds against the SwiftUI `Location.update` / `Binding.Box.update` crash family seen when searching and scrolling Splice results.

## Why

The Splice browser was still rendering dynamic MCP result rows with SwiftUI `ForEach` inside the inspector `ScrollView`. Pressing Return could update MCP results, and scrolling immediately after that could force SwiftUI to re-evaluate result row bindings while AppKit was recursively laying out the hosting view.

## Changes

- Replaced the SwiftUI result row list in the full Splice browser with an AppKit-backed result list.
- Result rows are now rebuilt as plain `NSView` rows, avoiding SwiftUI per-row bindings during scroll/layout.
- Preview/Web Preview buttons still call back into `AppState.previewSplice(_:)`.
- Tag buttons still update the local genre filter.
- Dragging rows still emits the Lemmings Splice pasteboard payload.
- Removed `@Bindable` usage from the Splice browser MCP settings panel.
- Replaced MCP URL/token/download-folder SwiftUI text fields with the isolated AppKit text field used for Splice search inputs.

## Notes

This is intentionally a pragmatic quarantine: Splice MCP and plug-in/web surfaces are now treated as plugin-adjacent UI that should not participate deeply in SwiftUI layout/binding churn while results are changing.
