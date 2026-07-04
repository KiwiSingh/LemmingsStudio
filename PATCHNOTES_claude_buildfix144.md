# Lemmings Studio — buildfix144 (Claude): you can finally SEE what's wrong + the real recording root cause

## 1. Errors weren't printing to the GUI — because there was no status display at all
`editStatus` / `recordStatus` / recorder diagnostics were *set* all over the code but
**rendered nowhere**. Added a real **status bar** at the bottom of the main window
(`LSStatusBar` in ProDAWShell) that shows the latest diagnostic, turns orange on problems,
and is text-selectable. Also made `AudioRecorder.lastError` fire an `onDiagnostic` hook on
the main queue (via `didSet`), so even the **async** warnings — the "+1.75s no input
callbacks", silent-stream restart, device-binding fallback — now reach the bar. Before, the
recorder wasn't `@Observable` and nothing read its error, so every message vanished.

## 2. The real reason recording has been broken across ALL three capture rewrites
**It's almost certainly code-signing, not the capture code.** `build.sh` was **ad-hoc
signing** (`codesign --sign -`). macOS ties the microphone (TCC) permission to the app's code
signature, and an ad-hoc signature **changes on every rebuild** — so the grant never
persists, and CoreAudio then returns silence through AudioQueue, AVAudioEngine, *and* AUHAL
identically, "no matter what input." That matches your symptom exactly.

`build.sh` now:
- signs with a **stable identity** when available (`$LEMMINGS_SIGN_IDENTITY`, or a self-signed
  cert named "LemmingsStudio Local"), so the mic grant sticks across rebuilds;
- adds a `com.apple.security.device.audio-input` entitlement;
- falls back to ad-hoc with a loud warning + exact steps (create the self-signed cert, or
  `tccutil reset Microphone com.magmavance.LemmingsStudio`).

See **RECORDING_TROUBLESHOOTING_claude.md** for the 2-minute fix.

## 3. Undo "doesn't do anything"
Added always-clickable **Undo / Redo buttons** in the new status bar, wired directly to
`undoLastAction()` / `redoLastAction()` — no keyboard/menu/focus routing to fight. If clicking
these works but ⌘Z didn't, it was a key-routing issue; if they don't, tell me and I'll know
the engine itself is the problem.

Note on "undo didn't undo the failed take": since buildfix141, an **empty take is discarded
automatically** (removed from the timeline) and returns no clip — so there's intentionally
nothing to undo. The status bar will now say "Recording created an empty take — discarded it.
<reason>". If you still see a lingering empty clip, that reason text tells us why.

## Build note
Authored without the Swift toolchain — expect minor Xcode fixups. All edits brace-balanced.
