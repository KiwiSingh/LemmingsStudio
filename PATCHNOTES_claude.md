# Lemmings Studio — stability + Splice patch (Claude)

Three surgical fixes. No architectural changes; everything else untouched.

## 1. Crash fix — Splice Sounds plugin no longer takes the app down
**File:** `Sources/LemmingsStudio/App/App.swift`

Your crash log was a null-deref (`splice::toBufferView(...)`, `KERN_INVALID_ADDRESS at 0x0`)
on a worker thread *inside* `Splice Sounds.component` — it embeds WebKit + a Rust/tokio
runtime + JUCE, and segfaults in its own preview/scroll path. You can't fix their binary,
but the app was hosting it with `.loadInProcess`, so the plugin's crash landed in
Lemmings' address space and killed it.

Now we instantiate hosted Audio Units **out-of-process** (`.loadOutOfProcess`), the same
sandboxing Logic/GarageBand use. If the plug-in crashes, it dies in its own host process
and Lemmings stays up. Falls back to in-process only if the sandbox load fails (some
AUv2-only plugins), and the status line tells you which mode you got.

## 2. Downloads actually work — presigned URL was being dropped
**File:** `Sources/LemmingsStudio/Generative/SpliceMCP.swift`

`download_asset` returns a presigned URL embedded in a sentence of prose. The old
`urls(from:)` called `URL(string:)` on the whole text block — which returns nil when the
string has spaces — so the URL was never extracted and you got "tool ran but no URL
returned."

- `urls(from:)` now peels embedded http(s) URLs out of prose with `NSDataDetector`
  plus a markdown-link regex.
- `remoteDownloadURL(...)` now prefers a real presigned/file URL (S3/CloudFront/media
  extension) over the splice.com *page* link.
- `download_asset` now also receives a `download_path` hint.

## 3. Better preview than the WebView (best-effort, honest)
**Files:** `SpliceMCP.swift`, `App.swift`

Splice gates preview audio and the MCP returns no preview URL, so a credit-free native
preview isn't always possible. What changed:

- When you open Web Preview, Lemmings now scrapes the page for a *real* playable audio
  URL (`og:audio`, `<audio>/<source>`, or a preview/stream URL in embedded JSON). If it
  finds one, it closes the browser and plays it **natively via AVPlayer** (scrub/loop,
  no credit used).
- If the page only exposes blob/MSE streams (the common case), it keeps the WebView.
- When a row resolves an `asset_uuid`, the existing native path already previews the
  downloaded file (first play spends one credit, then it's cached/free).

## Build note
Authored on Linux without the Swift toolchain, so this isn't compile-verified — expect
the usual minor Xcode fixups. The changes are deliberately small and localized to the
three areas above.
