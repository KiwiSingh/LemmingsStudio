# Splice MCP Login and Browser Polish

## OAuth callback behavior

Splice's remote MCP auth flow can return to `lemmingsstudio://splice-oauth`. On macOS, a custom URL scheme can accidentally appear to launch a new copy if the app bundle does not explicitly prohibit multiple instances or if the callback is not routed through the app delegate.

This build adds both safeguards:

- `LSMultipleInstancesProhibited` is written into the app bundle `Info.plist` during packaging.
- The `NSApplicationDelegate` receives URL-open events and relays them into the already-running SwiftUI app state.

The existing SwiftUI `.onOpenURL` path stays in place as a backup.

## Browser presentation

The Splice MCP response shape can vary between text blocks and structured JSON. The browser now parses and displays richer fields when the server returns them:

- preview URL
- artwork / thumbnail URL
- waveform URL
- pack / collection name
- creator / label
- sound type
- instrument
- duration
- BPM / key / tags

Rows now support inline preview playback through AVPlayer instead of only opening preview URLs in a browser.

## Limitations

This is still not Splice's official proprietary desktop UI. It is a native LemmingsStudio MCP browser using the metadata available from the MCP tools. If Splice's MCP result omits artwork, waveform, or preview URLs, the app falls back to a clean card placeholder and the sample page.
