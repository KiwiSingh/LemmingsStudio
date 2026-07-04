# Lemmings Studio — buildfix145 (Claude): the actual bug — AudioClip wasn't @Observable

Your "undo reveals the waveform" clue cracked it. **Recording was capturing audio the whole
time** — the bug was purely that the finished take never told SwiftUI to redraw.

## Root cause
`AudioClip` was the ONLY clip class not marked `@Observable` (Clip, StepPattern, Track, etc.
all are). So when `stop()` sets `clip.samples` and `clip.lengthBeatsOverride`, SwiftUI was
never notified — the timeline kept showing the empty 0.25-beat *provisional* clip (your "twin
blanks"). Hitting **undo** mutated `track.audioClips` (which *is* observed), forcing the
arrangement to re-render and finally re-read the clip — which is why undo "extended the track
and surfaced the waveform." That also explains "ankai!" instead of "Bankai!": what surfaced
was the stale **last-0.7s preview tail**, not the full committed take.

## Fixes (`Sequencing.swift`, `Recording.swift`)
1. **`AudioClip` is now `@Observable`.** A committed take's waveform and length now appear the
   instant recording stops — no undo needed.
2. **Live preview shows the FULL take as it grows** (throttled to ~12 Hz), instead of only the
   trailing 0.7 s. So "Bankai!" shows as "Bankai!" while recording, start included — no more
   "ankai!".

## What this means
If audio was reaching "ankai!", your **mic permission and capture are working** — the AUHAL
recorder + the buildfix144 signing guidance did their job; the take just wasn't being drawn.
With this, a normal record → stop should now show the full waveform immediately on the track.

The buildfix144 status bar and Undo/Redo buttons remain, so you can still see diagnostics and
undo by click.

## Build note
Authored without the Swift toolchain — expect minor Xcode fixups. All edits brace-balanced.
