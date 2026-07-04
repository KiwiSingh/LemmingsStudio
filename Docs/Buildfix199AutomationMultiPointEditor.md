# Buildfix199 — Automation Multi-Point Editor Repair

Fixes the buildfix198 regression where automation lanes could behave like they only accepted one breakpoint.

## What changed

- Replaced split tap/point-drag gestures with a single lane-level drag gesture.
- A click on empty lane space now always creates another automation point.
- A click near an existing point only selects that point.
- A point only moves after the pointer crosses a small drag threshold.
- The same click/drag semantics are applied to tempo automation and track/device automation.

## Why

The previous point-local high-priority gestures could win the event before the lane canvas handled additional point creation. That made breakpoint drawing feel broken after the first point.
