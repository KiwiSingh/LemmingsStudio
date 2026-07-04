# Splice Web Preview UUID Polish

Buildfix 54 makes the Splice browser more honest and more useful when MCP search results arrive as page-only cards.

## What changed

- Page-only Splice cards still use the embedded WebView for preview.
- LemmingsStudio now parses hidden Splice asset identifiers from page URLs more aggressively:
  - canonical UUIDs,
  - 32-character hex IDs,
  - `/sample/<id>`, `/samples/<id>`, `/sound/<id>`, and `/sounds/<id>` URL shapes,
  - asset/sample/sound/id query parameters.
- Hidden UUIDs are stored only in card metadata and are not shown to users.
- The WebView navigation delegate watches the loaded Splice page URL and updates matching cards if the page redirects to a UUID-bearing URL.
- Drag/drop becomes available only when a hidden UUID, local file, direct download URL, or official preview/download URL is present.
- Downloads/imports still use the authenticated MCP download/fetch path. Page URLs are never passed into an `asset_uuid` field.

## UX states

- **Web Preview**: preview is available through Splice's own page, but download is not available yet.
- **UUID Resolved**: LemmingsStudio has a hidden asset UUID and can attempt MCP fetch/download on drag.
- **Fetch on Drop**: direct fetch/download/local preview data is available.

