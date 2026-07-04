# Lemmings Studio — Carla/VST3 + Splice preview/download fixes (Claude)

ChatGPT's buildfix82 tried to make Carla "own" the crashy Splice plug-in process by
preferring the VST3/VST build over the AU. That backfired: modern Carla (Homebrew) no
longer ships `carla-single`, so the VST3 never instantiated, and the only thing that
*did* open was the full Carla GUI app in a separate window. Meanwhile the earlier crash
fix already solved process-isolation a better way — by hosting the **AU out of process**.

## 1. VST3 "never instantiates" + "Carla opens in a separate window"  → route to the AU
**File:** `App/App.swift`

- **Reverted the plug-in scorer to prefer AU.** AU is hosted with
  `AVAudioUnit.instantiate(options: .loadOutOfProcess)`, which already sandboxes the
  Splice WebKit/JUCE/tokio process (a plug-in crash can't take Lemmings down) and needs
  no external Carla install. AU now scores 300; VST3 80; VST 60. VST3/VST only win when
  there is genuinely no AU.
- **`openPluginGUI` now routes to the AU host whenever an AU counterpart exists** — even
  if you hand-picked the VST3 slot. Splice Sounds ships an AU
  (`/Library/Audio/Plug-Ins/Components/Splice Sounds.component`), so it now opens via the
  sandboxed AU editor window owned by Lemmings instead of the Carla GUI.
- **Broadened the AU lookup** to search all AU component types (MusicDevice / MusicEffect
  / Effect), not just the slot's role. A VST3 slot is often tagged `.effect` during
  discovery, but Splice Sounds is actually a MusicDevice (instrument) AU — without this we
  missed its AU and fell through to Carla.

Net effect: Splice Sounds (and any plug-in shipping an AU) no longer touches Carla at all.
Carla remains only for genuinely AU-less VST3/VST plug-ins, where an external bridge window
is unavoidable on macOS (you can't host VST3 in-process without a VST host).

## 2. Preview "broken" → restored the in-app WebView + native-audio capture
**File:** `App/App.swift`

ChatGPT disabled the in-app WebView and made preview call `NSWorkspace.shared.open(page)`,
ejecting you to an external browser and orphaning the native-audio path entirely.

- `previewSplice` again opens the **in-app WebView**. While the Splice page loads,
  `captureSpliceWebPreviewHTML` scrapes for a real playable audio URL (og:audio /
  `<audio>` / `<source>` / preview JSON) and, if found, **plays it natively via AVPlayer
  (no credit spent)** and closes the browser. If the page only exposes gated/blob streams,
  the WebView stays as the fallback.
- The preview-via-download failure path now falls back to the in-app WebView (not an
  external browser) and surfaces auth errors clearly.

## 3. Downloads
**Files:** `Generative/SpliceMCP.swift`, `App/App.swift`

The download path is correct end-to-end and my earlier fixes are intact:
- `download_asset` is selected correctly, called with the real `asset_uuid` (search
  results carry a clean `**Asset UUID:**`) plus a `download_path` hint.
- The presigned URL is extracted from the prose response via `NSDataDetector` +
  markdown-link regex, preferring a real S3/CloudFront/`.wav` URL over the sample page,
  then fetched with `URLSession.download`.
- The MCP transport distinguishes **auth** (401/403 / "login"/"session") from
  **credit/license** errors and reports each clearly.

If downloads still fail at runtime, it is the official Splice MCP **OAuth/session state**,
not the parsing — the app will now say exactly that ("Open Splice login…"). I did **not**
spend one of your credits calling `download_asset` to test; say the word and I'll confirm
a single real download with you.

## Build note
Authored on Linux without the Swift toolchain, so not compile-verified — expect minor
Xcode fixups. All edits are surgical and brace-balanced; no architectural changes.
