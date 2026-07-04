# Buildfix94 — Agent ADSR maps, more synth plug-ins, Voice AI capture, Utility presets, Arrangement precision

Scope: this patch intentionally avoids the Splice MCP/download/preview code.

## Agentic sound-design layer

- Added a sound-family classifier for pluck, stab, lead, supersaw, bass, 808/sub, keys, pad, and generic synth requests.
- Added explicit ADSR guardrails per family so model output cannot collapse envelopes into one-sample blips.
- Expanded the static agent parameter vocabulary beyond Serum/Serum 2 toward Vital, Phase Plant, Sylenth, Omnisphere, and other macro/performance synths.
- AU parameter lookup now tries a cross-synth alias map after the Serum map and before fuzzy fallback.
- Bass/808 recipes keep mono/low-end-focused defaults and suppress space FX unless requested.

## Voice AI

- Added in-app dry vocal capture to the Voice AI panel.
- The capture writes mono 44.1 kHz WAVs under `~/Music/Lemmings Studio/Voice Captures`.
- `Stop + Use` automatically selects the captured WAV as the input for voice-to-voice rendering.
- Updated dataset guidance to reflect a Kits-like flow: minimum 10 minutes, recommended 30 minutes, practical upper target 60 minutes, dry and consented.

## Utility device

- Utility now has invert-left, invert-right, and swap-L/R parameters in addition to gain, width, balance, and mono.
- Device Rack now shows quick Utility presets: Center, Hard L, Hard R, Mono, Phase Ø, and Swap.

## Arrangement View

- Added waveform vertical zoom independent of timeline zoom.
- Timeline zoom now reaches farther for detailed edits.
- Holding Option or Shift while dragging clips/resizing edges engages high-precision movement for micro-alignments and comb-filtered drum work.
