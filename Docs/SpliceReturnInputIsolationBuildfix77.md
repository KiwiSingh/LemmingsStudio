# Splice Return/Input Isolation Buildfix 77

This buildfix hardens Splice browser text entry after Return inside Splice search/plug-in-adjacent surfaces could trigger SwiftUI binding/layout recursion and crash the app.

Changes:

- Replaced SwiftUI `TextField(...).onSubmit` usage in the Splice browser with an AppKit-backed `SpliceIsolatedTextField`.
- Return is handled by the AppKit field delegate, updates local text, and defers the MCP search to the next main run-loop turn.
- Delete/Backspace remain local text editing operations and should not bubble into LemmingsStudio track deletion.
- Applied the same isolated text input to the mini Splice browser.
- Deferred MCP search launches so observable `spliceStatus` / `spliceResults` mutations are not made inside SwiftUI's text-submit/layout transaction.

This does not change the MCP server behavior itself, but it should stop the app from crashing just because Return was pressed inside the Splice UI.
