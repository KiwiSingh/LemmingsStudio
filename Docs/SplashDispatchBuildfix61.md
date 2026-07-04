# Splash dispatch buildfix 61

The floating splash panel now avoids Swift actor isolation diagnostics on Xcode beta SDKs by using explicit main-thread dispatch guards rather than exposing AppKit panel methods as `@MainActor` entry points.

This keeps the translucent FL-style splash behavior while preventing compile errors such as `call to main actor-isolated instance method 'show(relativeTo:)' in a synchronous nonisolated context`.
