# Arrangement clip resize buildfix89

Scope: Arrangement View only. Splice MCP/download/preview and Sound Agent files are intentionally untouched.

## Problem
Dragging from a clip edge could also trigger the whole-clip move gesture. That made a resize attempt move the clip instead of extending/trimming it, and because SwiftUI was receiving many tiny drag updates the interaction felt laggy.

## Fix
- Edge resize handles now have a wider invisible hit target while keeping the visible handle narrow.
- Clip body movement uses a normal `.gesture(...)` rather than `.simultaneousGesture(...)`, so a handle drag does not co-recognize as a move drag.
- MIDI and audio resize gestures set `resizingClipID` immediately and ignore redundant sub-point drag frames.
- Clip move gestures snapshot their start position and only mutate the model when the snapped beat actually changes.
- Engine rebuilds remain deferred until gesture end.

Expected behavior: drag the left/right edge to trim or extend; drag the clip body to move. Edge drags should no longer move the clip around.
