# Splice integration research + credits architecture

## What public docs suggest

- The official Splice MCP beta is the clean path for search/build/download from third-party AI clients. It says downloads use the user account and credits, while re-downloads are free and there is a 100-download rolling daily limit.
- Official DAW integrations such as Ableton Live and Studio Pro expose browser/search/preview/license workflows directly in the DAW. These are first-party/partner integrations, not documented as a public REST API.
- Splice Bridge and the Splice Sounds plug-in are the public DAW-facing fallback paths: Bridge syncs key/tempo with Splice Desktop, while the Sounds plug-in browses, auditions, licenses, and drags samples inside DAWs.
- The open-source `splicedd` project is useful as prior art for sample-browser UX, but its README says it does not require authentication, so it is not a safe model for authenticated credit-spending downloads.

## LemmingsStudio stance

LemmingsStudio should not scrape page URLs or fake `asset_uuid` values. Authenticated downloads should go through the official MCP download/licensing tool when it is advertised. A Splice page URL remains page-only unless the MCP response gives either a direct preview/download URL or a real UUID.

## Credits/account preview

Buildfix 48 adds a privacy-safe account probe. It looks for advertised MCP tools with account/credits/subscription/quota/usage semantics and calls them with no arguments. It then displays only non-sensitive fields such as credits, download quota, plan/tier, and usage. It intentionally suppresses email, username, display name, and full name fields. If no account/credits tool is exposed, the UI says so instead of guessing.
