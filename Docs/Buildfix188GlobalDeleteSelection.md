# Buildfix188 – Global Backspace/Delete Selection Command

## Problem
Backspace/Delete could be intercepted by focused text fields such as the tempo field. That meant a user could click/select an Arrangement clip or track, but if a tempo/number editor still owned first responder, Backspace edited the field instead of deleting the selected DAW object.

## Fix
- Promoted plain Backspace and Delete to main-window DAW edit commands alongside the existing global Tab routing.
- Added an AppDelegate-level key monitor that catches Backspace/Delete before AppKit field editors consume them.
- Routes the command through `NotificationCenter` to `AppState.deleteSelectedItem()` on the main actor.
- Keeps protected secondary surfaces safe: plugin/vendor windows, Carla/bridge windows, Splice/browser surfaces, and sheets are not hijacked.

## Behavior
- Backspace/Delete deletes the selected piano-roll notes, selected clip, selected tracks, or selected track using the same existing `deleteSelectedItem()` priority.
- Tempo/number text fields no longer steal the key when the user expects Arrangement deletion.
- Existing menu Delete command and in-view shortcut catcher remain as fallbacks.
