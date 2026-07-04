# Splice AppKit Tag Compile Buildfix 79

## Problem
Buildfix 78 moved Splice search results into AppKit-backed rows, but the helper
button subclass declared `var tag: String?`. `NSButton` inherits `tag` from
`NSControl` as an `Int`, so Swift treated the new property as an illegal override.

## Fix
The Splice result tag payload is now stored in `spliceTag` instead of `tag`.
The AppKit result row keeps using `NSControl.tag` untouched for AppKit internals.

## Validation
The edited Swift source tree parses with `swiftc -parse` in the container.
Full macOS/Xcode beta build still needs to run on the target machine.
