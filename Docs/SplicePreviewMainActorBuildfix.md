# Splice Preview Main Actor Buildfix

Buildfix 44 fixes a Swift concurrency compile failure introduced by the fetch-aware Splice preview path.

`previewSplice(_:)` calls the preview player helper, which mutates UI-facing preview state and is isolated to the main actor. The public preview entry point is now also marked `@MainActor`, matching its usage from SwiftUI button actions.
