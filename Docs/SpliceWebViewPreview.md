# Splice WebView Preview

LemmingsStudio keeps Splice preview and download paths separate:

- Preview uses an embedded `WKWebView` for page-only Splice MCP results. This renders Splice's own sample page inside LemmingsStudio instead of scraping public GraphQL endpoints or decoding unofficial preview streams.
- Download/import still uses the authenticated official Splice MCP download/fetch tool when the MCP result exposes a real hidden asset UUID, direct download URL, or local file path.
- Page-only cards are web-previewable but not drag-ready. Their drag payload is intentionally inert so users do not hit `asset_uuid` schema errors.
- The UI never exposes Splice account email, username, bearer tokens, or raw asset UUIDs.

This is the beta-safe compromise: working in-app preview for page-only search results while keeping licensing/downloads on the account-backed MCP path.
