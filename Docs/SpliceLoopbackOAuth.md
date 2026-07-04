# Splice OAuth loopback callback

LemmingsStudio now prefers a localhost OAuth callback for Splice MCP login:

- `http://127.0.0.1:53682/splice-oauth` by default, with nearby ports as fallback.
- The running app starts a tiny in-process callback listener before opening the browser.
- Browser login returns to that listener instead of the `lemmingsstudio://` URL scheme.

This avoids macOS LaunchServices opening a second copy of the app when the custom URL scheme is handled by a different app bundle path or a stale registration.

The custom URL-scheme handler remains registered as a backup path, but the normal Splice login flow should use the localhost callback so the existing running instance receives the OAuth code.
