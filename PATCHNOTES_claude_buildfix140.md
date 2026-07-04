# Lemmings Studio — buildfix140 (Claude): recording commit race, Splice filters/paging, undo coverage

Built on ChatGPT's buildfix139. Nothing in their AudioQueue capture, Sound Agent,
Demucs, AU hosting, Piano Roll, warp, or metronome work was touched except where noted.

## 1. Recording — fixed the real "brokey" bug (truncated takes)
**File:** `Audio/Recording.swift`

The AudioQueue capture itself was fine; the bug was at **commit time**. During a take,
each input buffer dispatches a live-preview update that sets `clip.samples` to only the
**last 32,768 samples** (~0.7 s tail). When you hit stop, `stop()` commits the full
`captured` array — but a preview block that fired microseconds earlier was still queued on
the main thread and ran *after* the commit, overwriting the finished take with that 0.7 s
tail. Net result: every recording came out ~0.7 s long no matter how long you played.

Fix: the live-preview update now bails unless `recording == true` **and** the clip is
still the active take (`clip === activeClip`). After `stop()` (which clears both), any
late preview block is ignored, so the committed clip keeps its full-length audio.

Note: during recording the on-clip waveform still shows a rolling ~0.7 s window (a
ChatGPT preview choice). The *committed* clip is now always the complete take. Say the
word if you want the live waveform to show the whole take as it grows.

## 2. Splice
**Files:** `Generative/SpliceMCP.swift`, `App/App.swift`, `Views/Panels.swift`

- **Loop / one-shot filter.** New segmented control (All · Loops · One-shots) wired to
  `describe_a_sound`'s `type` enum (loop/oneshot). The typed BPM box now also sends
  `bpm_min`/`bpm_max` (±3) to the server. All three map defensively — only sent when the
  live tool schema advertises the field, so a server shape change can't break search.
- **Removed the Splice Sounds / Bridge plug-in fallback** section entirely from the
  browser, plus its auto-scan on appear. (The backing methods are left dormant in
  App.swift so nothing else breaks; they can be deleted in a later pass.)
- **Page navigation + cleaner layout.** Results are now paginated (6 per page) with
  ‹ Page x of n › controls and a total count. The list height is bounded to one page, so
  rows can't overflow or overlap the panel the way a 15k-result list could. The official
  MCP returns one block per search (no server offset), so paging is over the locally
  filtered set; changing the search resets to page 1.

## 3. Undo / redo
**File:** `App/App.swift`

The undo engine (context-aware stack, paired undo+redo closures, Cmd+Z / Cmd+Shift+Z) was
already solid — the gap was *coverage*. Added proper undo/redo to discrete structural ops
that previously mutated state silently:
- **Move Track** (snapshots track order before/after).
- **Mute / Solo** (snapshots all tracks' mute/solo, so radio-style exclusive toggles undo
  correctly too).

Still on the TODO list (continuous, drag-style params that need gesture-coalescing so a
single drag = one undo step): track volume/pan, project tempo, device parameter tweaks. I
can do a focused pass on those next — they need start/end capture rather than per-frame
registration, which is why I didn't bolt them on here and risk a noisy undo stack.

## Build note
Authored without the Swift toolchain — expect minor Xcode fixups. All edits are surgical
and brace-balanced; the established two-param `.onChange` and macOS 14 APIs are used to
match the codebase.
