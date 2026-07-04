# Splice Page URL UUID Buildfix 52

Splice MCP sometimes returns `https://splice.com/sounds/sample/<asset>/<slug>` links instead of a separate `asset_uuid` field. LemmingsStudio now treats that `<asset>` path segment as hidden metadata when it is either a canonical UUID or a 32-character hexadecimal asset identifier.

The browser still never exposes the UUID to the user. It uses the parsed value only for official MCP preview/download/fetch calls. Page URLs are never passed directly into `asset_uuid` fields.

If a page URL does not contain a valid identifier, the sample remains WebView preview-only and drag/download stays disabled cleanly.
