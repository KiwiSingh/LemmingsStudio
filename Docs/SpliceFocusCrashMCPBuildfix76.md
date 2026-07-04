# Splice Focus / Crash / MCP Buildfix 76

This buildfix addresses beta-blocking Splice integration regressions found while testing Splice Sounds and Web Preview.

## Keyboard focus isolation

LemmingsStudio's global shortcut catcher now backs off whenever focus is inside:

- an attached sheet,
- a separate plug-in/editor window,
- an embedded WebKit preview,
- a Splice/Carla/Bridge/plug-in titled window,
- AU/WebKit editor subviews.

This prevents Backspace/Delete inside Splice Sounds from deleting LemmingsStudio tracks and prevents normal typing in a plug-in/search box from leaking into the DAW command layer.

## Web Preview crash hardening

The Splice Web Preview no longer uses a SwiftUI `.sheet` bound directly to the observable AppState URL while WebKit is mutating page state. It now opens in a separate AppKit `NSWindow` managed by `LemmingsSpliceWebPreviewWindowController`.

The window still:

- loads Splice's own page,
- captures page URLs,
- scans high-signal page HTML for hidden asset UUIDs,
- updates the selected Splice card when the official page exposes a usable asset identifier.

This avoids the SwiftUI `Binding.Location.update()` / recursive AppKit layout trap seen on macOS 27 beta.

## MCP download messaging

Tool-level MCP errors that mention login/session/auth now surface as Splice auth-required status instead of opaque bad responses. Tool-level license/credit/quota/subscription errors now explicitly mention that stale MCP sessions can look like credit failures even when the user's account has credits.

