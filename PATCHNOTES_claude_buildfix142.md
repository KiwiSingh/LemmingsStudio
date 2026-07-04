# Lemmings Studio — buildfix142 (Claude): device-targeted recording (the Audacity/PortAudio way)

Researched how Audacity (PortAudio), LMMS, Ardour, and Ableton handle input capture — see
RECORDING_RESEARCH_claude.md. Short version: the proven macOS primitive is the **AUHAL**
with `kAudioOutputUnitProperty_CurrentDevice`, and `AVAudioInputNode` already wraps it.

## Change
**File:** `Audio/Recording.swift`
- The recorder now **binds the selected device directly on the input node's AUHAL**
  (`AudioUnitSetProperty(inputNode.audioUnit, kAudioOutputUnitProperty_CurrentDevice, …)`)
  — the same mechanism Apple's TN2091 and PortAudio's CoreAudio backend use to target one
  device.
- **Removed the system-default-input promotion.** buildfix141 made AVAudioEngine follow
  your device by switching your Mac's *global* default input to it — which hijacked your
  mic everywhere. That's gone; we target the device locally instead.
- If a device can't be bound it degrades to the current default input with a clear status
  message (rather than silently doing the wrong thing).

Keeps the buildfix141 AVAudioEngine input-tap (PortAudio-style callback-accumulate),
empty-take discard, and the commit-race guard.

## Why this should fix "no matter what input I select"
The old paths either (a) hand-rolled AudioQueue that delivered no buffers, or (b) relied on
flipping the global default device. Now we bind the exact `AudioDeviceID` on the capture
AUHAL — the device-targeting method the established DAWs actually use.

## Build note
Authored without the Swift toolchain — expect minor Xcode fixups. Edits are surgical and
brace-balanced; uses standard CoreAudio/AudioToolbox symbols already imported in the file.
