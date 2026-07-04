# LemmingsStudio Windows — buildfix212 (Claude): Splice sample browser (via the Splice MCP)

Ports the macOS Splice integration to Windows: browse and pull Splice samples straight into the
project, powered by the official Splice MCP server.

## MCP transport (`Features/SpliceClient.cs`)
- **McpHttpClient** — a JSON-RPC 2.0 streamable-HTTP MCP client ported from the Mac
  `MCPHTTPClient`: `initialize` → `notifications/initialized` → `tools/list` → `tools/call`,
  with the `Mcp-Session-Id` handshake, `MCP-Protocol-Version: 2025-03-26`, Bearer auth, and
  both `application/json` and `text/event-stream` (SSE) response parsing. A 401/403 surfaces as
  an auth prompt.
- **SpliceClient** — `describe_a_sound` search (query + loop/oneshot + BPM range) and
  `download_asset`. The result parser matches Splice's real markdown listing (verified against a
  live response): name, BPM, key, duration, type, pack, tags, link, and **asset UUID**.

## OAuth (`Features/SpliceOAuth.cs`)
- Full RFC 8252 native-app flow ported from the Mac: discovers
  `/.well-known/oauth-authorization-server`, dynamically registers LemmingsStudio as a public
  PKCE client, opens the system browser, catches the redirect on a **loopback socket**
  (raw `TcpListener`, so no admin/URL-ACL needed), exchanges the code (S256 PKCE) for tokens,
  and persists/refreshes them under `%APPDATA%\LemmingsStudio\splice_oauth.json`.

## Browser UI (`Features/SplicePanel.cs`) + new "Splice" tab
- **Connect Splice** (browser login), text search with **type** + **BPM min/max**, a results
  list (Name / BPM / Key / Pack / Tags), **Open Sample Page**, and **Add to Project**.
- Add-to-Project confirms the credit spend, downloads the presigned file to
  `Documents\LemmingsStudio\SpliceSamples\`, and creates a new audio track + clip (length
  derived from duration × BPM), then refreshes the arrangement.

## Honest scope
- The OAuth + MCP handshake is faithful to the Mac and to the MCP spec, but it's the one piece I
  can't exercise on this Linux box (no browser/account), so it may need small real-world fixups
  (exact scope handling, an SSE quirk). Search parsing was validated against a live
  `describe_a_sound` response.
- Downloads spend Splice credits on first fetch (re-downloads are free); the UI always confirms
  first.
- Authored on Linux without the .NET toolchain — brace-balanced, standard
  HttpClient/TcpListener/System.Text.Json; expect at most minor fixups on first Windows build.
