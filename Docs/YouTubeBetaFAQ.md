# LemmingsStudio Beta FAQ for YouTube

## 1. Can this run on the MacBook Neo?

Yes — but with important expectations. MacBook Neo is a real macOS Mac, not an Intel Mac and not a Chromebook/iPad-style device. Apple lists it as an entry-level MacBook powered by the A18 Pro chip, with a 13-inch Liquid Retina display and up to 16 hours of battery life.

LemmingsStudio should be able to launch on MacBook Neo as long as it is running the required macOS version, but the Neo is the lightest Apple laptop in the lineup. Treat it as the **minimum/entry-level experience**, not the ideal machine for heavy DAW + AI workloads.

What should work reasonably:

- basic arrangement editing
- MIDI sequencing
- sample browsing
- light audio tracks
- automation editing
- basic export

What may be slower or more limited:

- large sample libraries
- huge projects
- stem splitting
- RVC/voice tools
- local AI models
- lots of plug-ins at once
- high track counts with effects everywhere

Recommended wording for viewers: **MacBook Neo should run the beta, but for serious LemmingsStudio use, an M-series MacBook Air/Pro with more RAM and storage is still the better choice.**

## 2. How much space do I need on my Mac to run this?

The app itself is big because it bundles DAW resources, Python tooling, stem-splitting support, AI/audio helpers, and optional model caches.

Recommended free space for the beta:

- Minimum practical install: 10–15 GB free.
- Comfortable install with bundled/preloaded models: 25–40 GB free.
- Heavy use with exports, stem splits, cached models, temporary renders, and large sample libraries: 50 GB or more free.

If installing to an external SSD, use an APFS-formatted SSD where possible. Large AI/stem models and sample-library scans will feel awful from a slow USB stick.

## 3. What is the minimum version of macOS I need to run this?

The current package target is macOS 14 Sonoma or newer.

Recommended:

- Minimum: macOS 14 Sonoma.
- Better: macOS 15 or newer.
- Beta/dev macOS builds may work, but they can also break audio, GPU, Python, or plug-in behavior in weird ways.

## 4. Why does macOS say the app is from an unidentified developer?

This is an early beta build. The DMG includes an installer helper that can remove quarantine and locally trust the app bundle. It may ask for your macOS password.

## 5. Can I install it on an external SSD?

Yes. Run `Install LemmingsStudio.command` from the DMG and choose the external-drive option. The helper will create an `Applications` folder on that drive if it does not already exist.

## 6. Does it support VST/AU plug-ins?

The Mac beta is focused on macOS Audio Units and the current hosted plug-in path. Some bridged or external plug-in workflows may still be experimental.

## 7. Is Windows supported yet?

Not yet. The Windows port is the next major work item after the Mac beta stabilizes. The Windows version needs a different UI/audio/MIDI/backend layer because the current app uses macOS technologies such as SwiftUI/AppKit/CoreAudio/AVFoundation.

## 8. Will Linux be supported?

Linux is planned after Windows. The Linux build will likely need a separate audio/MIDI backend and careful packaging for plug-ins, Python models, GPU acceleration, and distro differences.
