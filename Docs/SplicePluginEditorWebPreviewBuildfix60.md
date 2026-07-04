# Buildfix 60 — Splice plug-in editor + Web Preview UUID extraction

## Splice Sounds / Bridge fallback

The Splice fallback now attempts to open the actual AU vendor editor window after loading the detected plug-in on a LemmingsStudio track.

- `Open Sounds Plug-in` / `Open Bridge` load the chosen plug-in and request its AU editor view.
- The device rack `Open` button opens the AU editor instead of revealing `.component` in Finder when the plug-in is AU-hostable.
- The device rack `Use` button now sets the slot as the track target, rebuilds the engine, and opens the editor.
- Non-AU formats are still revealed in Finder because LemmingsStudio does not host VST/VST3 editor windows yet.

## Web Preview UUID extraction

The embedded Splice Web Preview now scans the loaded page's DOM/HTML after navigation finishes. This is still preview-only: LemmingsStudio does not decode or extract preview audio.

It extracts hidden Splice asset IDs from:

- navigation URLs,
- JSON-LD/script payloads,
- DOM HTML,
- `asset_id` / `asset_uuid` / `sample_id` / `sound_id` style fields,
- `/sample/<id>` and `/sounds/<id>` style paths.

When a UUID is found, the card is updated silently and becomes MCP-fetchable for authenticated download/import.
