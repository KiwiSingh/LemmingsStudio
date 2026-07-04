# Buildfix129 — Mic privacy + multichannel input safety

Fixes the first real audio-input crash path from buildfix127.

## Why the app crashed

macOS terminated the app through TCC because the app bundle did not include
`NSMicrophoneUsageDescription`. Any attempt to request/use microphone access
without that key is an immediate privacy crash.

## What changed

- `build.sh` now writes `NSMicrophoneUsageDescription` into the generated app
  `Info.plist`.
- Audio track recording still exposes a device picker and a per-track input
  channel picker.
- The recorder no longer tries to force a multichannel device format into the
  tap; it taps the input node natively and copies only the selected channel.
- For 4/6/8-channel devices like Revelator Dynamic, direct software monitoring
  is disabled instead of routing the whole interface into the stereo main mixer.
  Recording still captures the chosen channel.
- Arrangement track context menus now separate `Input Device` and `Input Channel`
  so picking the correct input is less cursed.

## Not touched

Splice, Sound Agent, Demucs/stems, AU hosting, Piano Roll, Mixer FX, metronome,
count-in, and browser code were not changed.
