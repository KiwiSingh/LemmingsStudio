# Buildfix 198 — Automation Click/Drag Semantics

Fixes automation editing so clicking and dragging are no longer conflated.

## Problem

Track/clip automation points used `DragGesture(minimumDistance: 0)`. In SwiftUI/AppKit this means a plain click can immediately enter the drag path, so clicking elsewhere on the automation lane could move the currently hit/selected point instead of creating a new breakpoint.

## Fix

- Automation points now require a real drag threshold before they move.
- Plain-clicking an existing point only selects it.
- Plain-clicking empty lane space creates a new automation point.
- New points are inserted into the lane and sorted, preserving the connecting path between all breakpoints.
- Canvas taps near an existing point select that point rather than accidentally creating a duplicate point.
- Tempo automation received the same click/drag split for consistency.

## Files changed

- `Sources/LemmingsStudio/Views/AutomationEditor.swift`
