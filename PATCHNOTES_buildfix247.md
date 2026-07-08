# LemmingsStudio buildfix247

## visionOS spatial Arrangement interactions

- Added clip movement with snap-aware pinch/drag gestures.
- Added left and right clip trim handles.
- Added persistent audio source-offset updates for left trimming and splitting.
- Added MIDI-note-aware clip splitting.
- Added audio clip splitting with correct source offset for the right-hand clip.
- Added clip duplication and deletion.
- Added context menu actions for split, duplicate, and delete.
- Added snap choices: 1 Bar, 1/4, 1/8, 1/16, 1/32, Off.
- Added horizontal magnification zoom and vertical track scaling.
- Added detachable Clip Inspector window.
- Added experimental volumetric Spatial Control Deck.
- Added gaze/pinch-friendly hover/focus affordances.

## Command-line builds

`Ports/visionOS/build-visionos.sh` now uses `xcodebuild` with modes for:

- simulator
- generic simulator / CI
- generic visionOS device
- release archive
- scheme/destination listing

The Xcode project is generated with XcodeGen before `xcodebuild` is invoked.

## Compatibility architecture

The Desktop Plug-in Bridge abstraction remains intact. Native AU, native VST3, and experimental Wine compatibility providers remain isolated behind the bridge seam rather than being embedded into the visionOS app itself.

## Validation note

The source was structurally inspected in the Linux build environment. Real compilation requires Xcode plus the visionOS SDK/runtime and must be validated on macOS.
