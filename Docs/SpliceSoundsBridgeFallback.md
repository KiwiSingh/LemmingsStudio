# Splice Sounds / Bridge fallback

Buildfix 53 adds an optional Splice DAW plug-in fallback to the Splice panel.

## Why this exists

Splice MCP can return page-only results depending on the advertised tools and response shape. Those results are still useful for WebView preview, but they are not always enough for drag/download unless MCP exposes a valid hidden asset UUID or download/fetch tool output.

Splice’s official DAW-side tools already solve part of this workflow:

- Splice Bridge previews Splice Desktop sounds inside the DAW, synced to project tempo/key.
- Splice Sounds Plug-in can browse, preview, license, and drag sounds inside supported DAWs.

## What LemmingsStudio does

- Scans standard macOS AU/VST/VST3 folders for Splice Sounds / Splice Bridge / Splice Listener plug-ins.
- Shows detected plug-ins in the Splice panel.
- Lets the user open the Sounds plug-in or Bridge on a new track.
- Keeps MCP as the official authenticated download/licensing path.
- Does not inspect browser cookies, scrape Splice sessions, or read private plug-in state.

## Intended beta behavior

Use the Splice plug-in fallback for auditioning and official in-DAW Splice workflows when MCP only returns page-only cards. Use MCP for any direct LemmingsStudio download/import that needs account credits/quota.
