# Splice OAuth single-instance routing

Splice MCP login uses the `lemmingsstudio://splice-oauth` callback because that is the redirect path that actually returns an authorization code from the current Splice flow.

To stop macOS from launching some other copied build folder when the browser opens that callback, LemmingsStudio now registers the currently-running app bundle with LaunchServices on startup and immediately before opening the OAuth login page.

The localhost handoff listener remains as a last-resort fallback, but the intended path is now:

1. Launch the app the user is actually testing.
2. Register that exact app bundle as the handler for `lemmingsstudio://`.
3. Open the Splice browser login.
4. Browser callback returns to the already-running instance.

This matters when multiple unpacked beta builds exist on disk with the same bundle identifier.
