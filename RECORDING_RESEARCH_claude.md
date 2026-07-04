# How the open-source DAWs actually record — and what we took from it

You asked me to look at Audacity / LMMS / Ableton and replicate the proven approach.
Here's what each one really does on macOS, and the concrete change it drove.

## Audacity → PortAudio → AUHAL (this is the one worth copying)
Audacity doesn't talk to CoreAudio directly; it uses **PortAudio**, whose macOS backend
lives in `src/hostapi/coreaudio`. PortAudio's record model is dead simple: open a stream,
get a **callback** delivering input buffers (it supports 32-bit float natively), and
**accumulate them into an array** (`paex_record.c`'s `paTestData { recordedSamples,
frameIndex }`). That's exactly our model: tap → append floats → commit on stop.

Under the hood on macOS, PortAudio uses the **AUHAL** — `kAudioUnitSubType_HALOutput`
configured for input (Apple Technical Note **TN2091**):
- open the HAL output unit, enable IO on the **input** element (1), disable output (0),
- **set `kAudioOutputUnitProperty_CurrentDevice` to a specific `AudioDeviceID`** to target
  one device,
- the AUHAL flattens the device into a **de-interleaved** stream and has a built-in
  converter, so you can ask for float and it converts,
- optional **channel map** to pick specific channels.

Worth noting: Audacity **can't even choose a specific input channel** ("Audacity will
simply use the first ones it finds"). Our per-channel copy is already ahead of it.

## LMMS → not a useful reference for recording
LMMS uses PortAudio/SDL/JACK for **output**, but historically has **no audio-input /
wave-recording capability** at all — its own forum tells people to use **Ardour** (a
JACK-based engine) or record in Audacity and import. So there was nothing to copy here.

## Ardour → the real pro reference
Ardour is the serious open-source recording DAW; it runs on JACK / its own backend with a
realtime callback pulling from the device. Same callback-accumulate shape, heavier engine.
Good north star, too big to port wholesale.

## Ableton → nothing to replicate for recording
Ableton's audio/recording engine is **proprietary and closed**. The only open pieces are:
- **Ableton Link** — tempo/beat sync, which Ableton themselves open-sourced (not recording),
- community **.als** decoding — but a `.als` is just **gzipped XML** (the project file),
  nothing about input capture.
So there is no "decoded Ableton recording" to borrow. (If you ever want tempo sync across
apps, Link is the thing to integrate — separate feature.)

## What we changed as a result
macOS's reliable, device-specific recording primitive is the **AUHAL with
`kAudioOutputUnitProperty_CurrentDevice`**. The clean way to get it from Swift without a
full C render-callback rewrite: **`AVAudioInputNode` already wraps that exact AUHAL**, so
you can set the device straight on `inputNode.audioUnit`.

- buildfix141 already moved capture to an **AVAudioEngine input tap** (the PortAudio-style
  callback-accumulate model).
- buildfix142 now **binds the chosen device directly on the input node's AUHAL** via
  `kAudioOutputUnitProperty_CurrentDevice`, and **stops promoting your device to the global
  system-default input** (that old hack hijacked your Mac's mic system-wide). This is the
  TN2091/PortAudio device-targeting approach, just reached through AVAudioEngine.

If we ever want the *last* mile of robustness (sample-rate-mismatch handling, exact channel
maps, zero AVAudioEngine quirks), the next step is a standalone AUHAL + render callback —
the literal PortAudio approach. Happy to do that if the tap path still misbehaves on any
specific interface.
