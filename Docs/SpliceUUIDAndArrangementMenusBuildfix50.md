# Buildfix 50 — Splice UUID resolution + Arrangement context menus

## Splice

Splice MCP search results may return page links before/without a real `asset_uuid`. LemmingsStudio must not pass a `splice.com/sounds/sample/...` URL into an `asset_uuid` parameter, because the official MCP schema validates UUID format.

This build keeps asset UUIDs hidden from the user-facing browser card, but preserves them in raw metadata when the MCP response provides one. If a user drags or previews a page-only result, the client now tries to resolve the hidden UUID through the official MCP search/details path before calling the download/license tool. If no UUID can be resolved, it shows a clean status instead of making an invalid MCP call.

## Arrangement context menus

The Arrangement view now has DAW-style right-click menus:

- Empty Arrangement area: add Audio, MIDI, Sequencer, Drum Machine, or Dubstep Wrangler tracks.
- Track header / lane body: rename, duplicate, freeze/unfreeze, bounce in place, create track, delete track.

These are intentionally generic DAW behaviors, not brand-specific UI copying.
