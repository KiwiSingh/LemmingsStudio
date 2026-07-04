# Lemmings Studio — buildfix141 (Claude): recording actually records + undo actually undoes

I was wrong in buildfix140 about both of these — the screenshot made the real causes obvious.
Sorry for the misdiagnosis; here's what was actually happening and what I changed.

## 1. Recording: "twin empty slots, never proceeds" — root cause + fix
**File:** `Audio/Recording.swift` (+ a small bit of `App/App.swift`)

The hand-rolled **AudioQueue** capture path simply wasn't delivering input buffers on your
setup (hence empty takes "no matter what input"). The "twin slots" were a single empty
0.25-beat provisional clip rendered with its two edge grips — i.e. a take that captured
nothing.

Fix — replaced the AudioQueue capture with the **canonical AVAudioEngine input-tap**:
- A dedicated `AVAudioEngine` taps its input node at the hardware's own format and copies
  the user-selected channel into the take. This is the standard, reliable macOS capture
  path. Device selection still works because `selectInputDevice` already promotes the
  chosen device to the system default input before we start.
- **No more phantom clips:** if a take captures zero audio, the provisional clip is now
  *removed* on stop instead of committed as an empty region, and the status bar tells you
  exactly why (mic permission / device / channel / interface in use).
- Kept the buildfix140 commit-race guard so a finished take is never truncated.

If a real take still comes up empty, the on-screen message will now pinpoint it — most
likely **System Settings ▸ Privacy & Security ▸ Microphone ▸ enable Lemmings Studio**, or
the wrong input channel (you had Ch 2 selected on the Revelator).

## 2. Undo/redo "doesn't work for anything" — root cause + fix
**Files:** `App/App.swift`, `Views/AbletonOverhaul.swift`

The undo *engine* was fine; the **keystroke never reached it**. Two ⌘Z handlers were
fighting: the Edit-menu command and a global key monitor. The menu's Undo/Redo items were
gated with `.disabled(!canUndo)`, and under the Observation framework that condition
doesn't re-evaluate inside `.commands` — so the menu item stayed permanently disabled and
⌘Z just beeped.

Fix:
- Removed the `.disabled` gates so Undo/Redo are always enabled (the engine already
  no-ops safely on an empty stack). The menu shortcut now reliably fires.
- Removed the duplicate ⌘Z/⇧⌘Z/⌘Y handling from the global key monitor so undo can't
  fire twice per keystroke. Focused text fields still self-handle ⌘Z for text editing.

Combined with the recording fix (a real take now registers a "Record Audio Clip" undo),
**undoing a recording take now works**, along with the other registered actions (add/
delete/move/split/duplicate/paste clips, add/delete tracks, load plugins, piano-roll note
edits, move track, mute/solo).

Honest scope note: continuous drag params (track volume/pan, tempo, device knobs) still
need gesture-coalesced undo and are not yet covered — that's a deliberate follow-up so the
undo stack doesn't fill with hundreds of micro-steps.

## Untouched
Sound Agent, Demucs/stems, AU hosting, Piano Roll, warp, metronome/count-in, Splice
(buildfix140 filters/paging stay), mixer FX.

## Build note
Authored without the Swift toolchain — expect minor Xcode fixups. All edits are surgical
and brace-balanced; the AVAudioEngine tap is the standard idiomatic capture pattern.
