# Splash MainActor Buildfix 59

The floating splash panel methods are `@MainActor`, so any `AppState` methods that create or dismiss that panel must also execute on the main actor.

This fixes Swift 6/Xcode beta diagnostics where `showStartupSplashIfNeeded()` and `finishSplashScreen()` synchronously called main-actor-isolated `LemmingsSplashWindowController.show(relativeTo:)` and `.dismiss()`.

No splash UI behavior changed in this buildfix: it still uses the separate translucent floating splash panel introduced in buildfix 58.
