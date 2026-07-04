# Splice Download Retry Buildfix 71

Fixes a failure mode where Splice's official MCP download tool returned only:

> download failed; please try again

The browser previously surfaced that as a generic "no local file path or downloadable URL" error. It also trusted UUID-looking tokens from arbitrary WebView HTML too aggressively.

Changes:

- WebView HTML UUID detection no longer promotes random UUID-looking tokens from the page as asset IDs.
- Only high-signal `asset/sample/sound` fields or Splice sample/sound URL paths unlock MCP download.
- If the official download tool returns an explicit failure string, LemmingsStudio now re-resolves the sample through official MCP search/details once and retries the download with that hidden asset UUID.
- If Splice still fails, the status now says the official download tool failed and suggests retry/login/credits or the Web Preview / Splice Sounds fallback.
