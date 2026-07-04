# Buildfix189 — Arrangement-scoped Delete/Backspace with protected Splice text entry

## Problem
Buildfix188 made Backspace/Delete global enough that focused browser/search text entry could still be pre-empted by Arrangement clip/track deletion. That fixed the tempo-field annoyance but was too broad for Splice search and other browser-adjacent text fields.

## Fix
Backspace/Delete is now scoped to Arrangement editing only:

- The app-level key monitor only swallows Backspace/Delete when the active workspace is `Arrangement`.
- The actual delete handler double-checks `workspace == .arrangement` before deleting anything.
- The SwiftUI shortcut catcher also checks the current workspace before firing its delete closure.
- Splice isolated text fields mark themselves as protected text-entry while editing, so Backspace stays normal text deletion in Splice search/filter/token fields.
- Embedded protected surfaces are still detected by responder/view hierarchy checks, not just window titles.

## Intended behavior
- Arrangement View + selected clip/track + Backspace/Delete → deletes the selected Arrangement item.
- Splice search/filter/token field + Backspace → deletes text in the field only.
- Non-Arrangement workspaces + Backspace/Delete → no clip/track deletion.
- Plugin/Carla/bridge/browser surfaces keep their own key handling.
