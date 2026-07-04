# Buildfix 186 — Global Tab Workspace Switch

## Problem

Main-window text fields could still intercept `Tab` for AppKit field-editor focus traversal before the DAW workspace switch fired. That made the shortcut feel inconsistent: clicking into search/BPM/config fields could stop `Tab` from switching views.

## Fix

`Tab` is now captured by an app-level local key monitor installed by `AppDelegate`, before text fields get to consume it.

- Plain `Tab` cycles workspaces forward.
- `Shift-Tab` cycles workspaces backward.
- The event is swallowed after routing, so `NSTextField`/`NSTextView` cannot use it for focus traversal or insert a tab.
- Protected secondary windows are excluded so vendor plug-in editors, Carla/bridge windows, Splice/browser surfaces, and sheets are not hijacked.

## Files changed

- `Sources/LemmingsStudio/App/App.swift`
- `Sources/LemmingsStudio/Views/AbletonOverhaul.swift`
