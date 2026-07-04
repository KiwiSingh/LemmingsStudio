# Splicedd research + Splice browser design notes

## What splicedd appears to do

`ascpixi/splicedd` describes itself as a custom Splice frontend that “does not require any kind of authentication.” Its public source does not show OAuth, browser-session import, cookie handoff, or a native Splice login flow. The frontend posts directly to Splice's public `https://surfaces-graphql.splice.com/graphql` endpoint with a `SamplesSearch` GraphQL query.

The same project fetches `preview_mp3` file URLs from the GraphQL result and decodes a scrambled MP3 preview with a local XOR-style decoder before writing a WAV for drag-and-drop. That is useful research for understanding why its UI can preview and drag without login, but it is not the same thing as licensing or downloading a user-owned full-quality sample through an authenticated Splice account.

## Policy for LemmingsStudio

LemmingsStudio should not copy that unauthenticated fetch/download path. The supported path is:

1. Use Splice's official remote MCP endpoint.
2. Authenticate with the user's Splice account through OAuth/browser auth.
3. Use only advertised MCP tools for search, preview, license/download, account/credit/quota info, and local file outputs.
4. Never pass a `splice.com/sounds/sample/...` page URL as an `asset_uuid`.
5. Never show email, username, display name, or full name when account/credits info is displayed.

## UI ideas borrowed safely

The UI direction borrowed from splicedd/splicerr is limited to generic sample-browser patterns, not GPL code:

- large sample cards
- cover/waveform emphasis
- one-tap preview/open action
- visible BPM/key/type chips
- clickable tags for quick filtering
- drag-first workflow instead of an Import button
- clear page-only vs fetchable status

## Why page-only results remain page-only

If official MCP search returns only a web page link, the app can open that page but should not treat it as a licensed/downloadable asset. Drag-to-DAW should require at least one of:

- a real UUID matching `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
- a direct preview/download URL returned by the official tool
- a local file path returned by the official tool
- an advertised MCP download/license/fetch tool that accepts the result's real ID
