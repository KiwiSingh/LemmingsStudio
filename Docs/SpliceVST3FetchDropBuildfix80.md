# Splice VST3 + Fetch-on-Drop Stabilization Buildfix 80

This build moves Splice fallback behavior away from the crash-prone AU/WebView path:

- Splice Sounds / Bridge fallback now prefers VST3, then VST, and only then AU.
- Explicitly selected Splice VST/VST3 plug-ins are no longer silently replaced with matching Audio Units.
- VST/VST3 Splice plug-ins stay behind the Carla bridge process boundary.
- Splice result rows always drag the same `lemmings-splice-sample:` payload, even when the row was originally page-only.
- Arrangement and Step Sequencer drops now attempt official MCP fetch/resolve on drop instead of requiring Web Preview first.
- Arrangement drop handling accepts additional text pasteboard representations from AppKit-originated drags.
- Embedded WebView preview is no longer the primary UX; page-only previews open externally while Lemmings keeps MCP as the licensing/download path.

Notes:

- The app still does not ship unauthenticated Splice GraphQL scraping or scrambled-preview decoding. Preview/download import remains official-MCP-first, with Splice's own plug-in as the manual fallback.
- If MCP reports login/credit errors despite a valid paid account, the next likely fix is OAuth/session refresh and better account diagnostics, not WebView scraping.
