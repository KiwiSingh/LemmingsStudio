# Splice remote MCP auth discovery

LemmingsStudio treats Splice as a remote streamable HTTP MCP provider at:

```json
{
  "mcpServers": {
    "splice": {
      "type": "streamable-http",
      "url": "https://mcp.splice.com/mcp"
    }
  }
}
```

When the app probes the endpoint for browser login, Splice may return OAuth protected-resource metadata like:

```json
{
  "resource": "https://mcp.splice.com/mcp",
  "authorization_servers": ["https://mcp.splice.com"],
  "scopes_supported": ["openid", "profile", "email", "offline_access"]
}
```

That JSON is not a login URL. It tells the MCP host where to discover the authorization server. The app now:

1. Reads `authorization_servers[0]`.
2. Tries `.well-known/oauth-authorization-server` and `.well-known/openid-configuration` on that issuer.
3. Applies `authorization_endpoint`, `token_endpoint`, `registration_endpoint`, and supported scopes when present.
4. Attempts OAuth dynamic client registration when `registration_endpoint` is advertised.
5. Falls back to opening the authorization server / official Splice MCP page when Splice does not expose public native-app registration metadata.

Do not ask users to paste bearer tokens from Cursor, Claude, Vesktop, or browser sessions. The normal UX should stay browser-auth first, with token fields kept as partner/debug fallback only.
