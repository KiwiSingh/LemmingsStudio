# Lemmings Studio — buildfix84: the REAL download bug (Claude)

## TL;DR
Downloads failed with "can't fetch the UUID at all" because of a **markdown
cleanup ordering bug**, not auth and not credits. Splice returns each field as
`**Asset UUID:** <uuid>`. The old `cleanedMarkdownLine` stripped ONE leading
bullet (`^[-*•]`) *before* removing `**`, so `**Asset UUID:**` became
`*Asset UUID:` — a stray leading `*`. The anchored matcher `^asset uuid\s*:`
then never matched, so the UUID was dropped for **every** row, and the download
bailed before ever calling `download_asset`.

Proven with a Python port of the exact parser against a live Splice response:
- **Before:** `value('asset uuid')` → `None` for all rows.
- **After:** 10/10 rows yield a fetchable asset UUID.

## The fix (SpliceMCP.swift · cleanedMarkdownLine)
Reordered: strip `**` / `__` FIRST, then `^#{1,6}`, then `^[-*•]+` (now tolerates
multiple leading bullets). `**Asset UUID:** fd1f…` → `Asset UUID: fd1f…` → parses.
Bonus: `**Pack:**`, `**Tags:**`, `**Link:**` were silently breaking the same way —
those parse correctly now too, so Pack/Creator/Tags populate again.

## Also in this build (carryover from buildfix83)
1. **Carla/VST3 "separate window" + "VST3 never instantiates"** — reverted the
   chooser to prefer the AU (it's hosted `.loadOutOfProcess`, already sandboxed),
   and `openPluginGUI` now routes any plug-in to the AU host when an AU counterpart
   exists (broadened AU lookup across all component types). Splice Sounds opens via
   the sandboxed AU window; Carla is only for genuinely AU-less plug-ins.
2. **Preview regression** — `previewSplice` was ChatGPT-routed to an external
   browser; restored the in-app WebView + native-audio capture (plays via AVPlayer
   with no credit when the page exposes a playable URL).

## Still unverified (needs you / a credit)
The final `download_asset` round-trip itself. With UUIDs now extracted, the path is:
search → asset_uuid present → `download_asset` → presigned URL → fetch. I did NOT
spend a credit to test the live fetch. Say the word and I'll confirm exactly one
real download with you.

## Build note
Authored without the Swift toolchain — expect minor Xcode fixups. Edits are
surgical and brace-balanced.
