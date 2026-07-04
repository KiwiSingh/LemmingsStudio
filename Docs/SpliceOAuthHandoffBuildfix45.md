# Splice OAuth Handoff Buildfix 45

Splice login now returns to the custom `lemmingsstudio://splice-oauth` callback again, because the Splice MCP OAuth server may not reliably redirect to arbitrary localhost callbacks.

To avoid LaunchServices spawning a second working copy, the app also starts a tiny localhost handoff listener. If macOS opens a new LemmingsStudio copy for the custom callback, that copy forwards the callback to the already-running instance over localhost and then exits.

This keeps the previously-working Splice auth flow while still avoiding duplicate app instances during OAuth.
