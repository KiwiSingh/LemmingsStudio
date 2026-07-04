# Buildfix105 — Device browser categories + MIDI/audio effect clarity

## Verification

The device previously referred to as the arpeggiator is actually registered as:

```swift
case arpeggiator = "Pattern Arp"
```

So the user-facing device name is **Pattern Arp**, not plain “Arpeggiator.”

## Browser/rack changes

- Built-in devices are now grouped by category instead of dumped in enum order.
- Devices are alphabetized inside each category.
- Rows explicitly show whether they are an **Audio Effect**, **MIDI Effect**, **Instrument**, **Rack**, **Analyzer**, **Generator**, or **Bridge**.
- Device Rack “Add Device” and clip “Add Clip FX” menus use the same grouped ordering.
- Clip FX menu is restricted to audio/analyzer-safe devices instead of offering every instrument/MIDI device.

## MIDI effect implementation pass

The previously shell-only MIDI devices now expose parameters and are read by the render scheduler:

- Pattern Arp: octave expansion / arp-style pitch fanout.
- Chord Builder: third, fifth, seventh, octave additions.
- Pitch Tool: semitone/octave transposition.
- Scale Mapper / Pitch Corrector: project-scale snapping.
- Velocity Mapper: gain/compression shaping.
- Note Gate Length: note-length/gate scaling.
- Note Randomizer: deterministic pitch variation.
- Note Bounce: fifth/octave bounce expansion.

## Stock shell cleanup

- Analyzer/modulator devices now use an analyzer utility shell with peak/RMS/activity readbacks.
- Rack devices now use a rack pass-through shell with chain and macro parameters.
- Granulator/Looper now route to the existing repeat/buffer DSP tier instead of falling through to the generic gain-only placeholder.

## Untouched

Splice MCP/download/preview code was not changed.
