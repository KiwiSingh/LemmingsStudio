# Splice Remote MCP Integration

LemmingsStudio treats Splice as a remote MCP provider, not as a static REST API.

Supported endpoint:

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

## UX rules

- Show **Connect Splice** and **Reconnect** buttons.
- On auth-required responses, open Splice's browser login/docs flow and ask the user to retry after sign-in.
- Do not ask users to paste bearer tokens copied from Claude, Cursor, Vesktop, or any other MCP host.
- Keep debug/partner token fields hidden behind advanced settings only.
- Store any future official session material in the macOS Keychain, not plaintext preferences.

## Current beta implementation

The in-app MCP client speaks JSON-RPC over streamable HTTP to `https://mcp.splice.com/mcp`, keeps MCP session IDs returned by the server, handles SSE-style `data:` responses, and discovers tools dynamically through `tools/list`.

Full hands-off browser session capture still depends on Splice exposing or documenting the exact OAuth/authorization-server metadata for third-party native MCP hosts. Until then, LemmingsStudio should prefer the official remote MCP endpoint and clearly label manual token flows as unsupported debug fallbacks.
