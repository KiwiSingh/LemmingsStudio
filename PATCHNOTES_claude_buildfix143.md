# Lemmings Studio — buildfix143 (Claude): standalone AUHAL recorder + honest patch agent

## 1. Recording → real C-style AUHAL (the PortAudio/Audacity way)
**File:** `Audio/Recording.swift`
Replaced the AVAudioEngine tap with a **standalone CoreAudio HAL output unit configured for
input** (`kAudioUnitSubType_HALOutput`) + a C render callback — exactly what PortAudio's
macOS backend (and therefore Audacity) does under the hood (Apple TN2091):
- open AUHAL → **EnableIO** input(bus 1)=1, output(bus 0)=0,
- **bind the exact `AudioDeviceID`** via `kAudioOutputUnitProperty_CurrentDevice` (falls back
  to the current default input with a clear message if a device can't be resolved),
- read the device's hardware input format, request **de-interleaved Float32** on the output
  scope of bus 1 (AUHAL's built-in converter handles the rest),
- pre-allocate an `AudioBufferList`, pull frames with `AudioUnitRender` in the callback, copy
  the selected channel, append.

This is fully independent of AVAudioEngine, so nothing in the playback graph (or a second
engine accessing `inputNode`) can contend for the input device — the most likely reason the
tap kept coming up empty. Keeps the empty-take discard, commit-race guard, and the silent-
stream restart/diagnostic.

## 2. Voice-to-voice / Voice AI recording — already covered
Verified the AI/voice capture path uses the **same `AudioRecorder`** (the AI panel's input
picker just sets `track.audioInputDeviceUID`, then runs `recorder.start`). So this AUHAL fix
applies to voice-to-voice takes automatically — no separate capture path to patch.

## 3. Metronome / count-in — not the blocker
Checked: count-in drives the **output** click only (`startCountInClick`/`stopCountInClick`)
and the count-in path still reaches `beginRecording → recorder.start`. No HogMode, exclusive-
mode, or session grab anywhere that would starve the input. Cleared as a suspect.

## 4. Patch agent: Rhodes-style requests no longer default to square garbage
**Files:** `Generative/DeviceTranslationLayer.swift`, `Generative/Agents.swift`
- Electric-piano/Rhodes recipes now push the oscillators to the **pure sine end**
  (`Osc A/B WT Pos → 0.0`) instead of 0.10/0.12, which on Serum's default table sat closer to
  saw/square.
- Added an **honest caveat**: when a request's timbre lives in the oscillator's *wavetable*
  (Rhodes, e-piano, acoustic piano, FM/DX, bells, organ, guitar, strings, brass, vocal) and
  the target is a wavetable synth (Serum/Vital/Sylenth/Omnisphere/Phase Plant), the agent now
  tells the user it can shape envelope/octave/FX but **cannot load the core wavetable via host
  automation**, and to load an EP/FM wavetable or a matching preset. No more silently shipping
  a sine-with-FX labeled "Rhodes."

## Build note
Authored without the Swift toolchain — expect minor Xcode fixups. All edits brace-balanced;
the AUHAL recorder uses standard AudioToolbox/CoreAudio symbols already imported in the file.
