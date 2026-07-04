# Buildfix 173 — Full-fat Windows feature-parity source package

This build turns the earlier Windows installer preview into a much fatter native Windows source tree that can be compiled into an installer while the remaining audio-engine parity work continues.

## Added Windows source layers

- Native .NET 8 WinForms shell with DAW-style tabs.
- Arrangement canvas with Explorer drag/drop, clip blocks, marquee selection, and clip inspector selection.
- Project model for tempo/key, tracks, clips, devices, automation lanes, and global automation.
- Save/open support for `.lemmingsproject` JSON documents.
- Progressive User Library scanning that populates batches while scanning.
- Browser tree with drag-out into Arrangement.
- Mixer list with mute/solo/arm/volume/pan state.
- Automation panel with global tempo and Device On lane representation.
- Stem-split backend invocation hooks through the Windows backend scripts.
- Backend installer/smoke-test path for CPU, DirectML, and CUDA.

## Full parity target

The Windows tree is now structured as a full-fat native port target rather than a placeholder launcher. The macOS app is still the reference implementation for the complete working engine. The Windows port now has enough real source structure to compile an installer, open/save project data, drag files into an arrangement, scan large libraries progressively, call backend scripts, and continue porting the engine/UI feature-by-feature.

## Not touched

No macOS stem splitter logic, stem packaging, recording, code signing, Splice, Serum/Serum 2/plugin fixes, AU hosting, RVC/build.sh, export, mixer clipping, warp controls, metronome/count-in, Finder import, MIDI learn, automation, or User Library scanning logic was changed.
