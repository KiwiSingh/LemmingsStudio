# Buildfix 168 — MIDI Learn, Pitch Bend Mapping, and MIDI Sanity Monitor

Scope guard: this buildfix intentionally does **not** touch stem splitter logic, stem packaging, code signing, recording, Splice, hosted plug-ins, export, warp, metronome/count-in, or Finder import.

## MIDI learn

Device parameter sliders now expose a right-click context menu with `MIDI Learn…`.

When MIDI Learn is armed, the next supported hardware gesture becomes the mapping source:

- MIDI CC knob/slider
- pitch-bend wheel / joystick / touch strip

The Settings → MIDI pane shows the current learn target and includes a Cancel Learn button.

## Pitch bend as automation/control source

Pitch bend is now treated as a high-resolution MIDI control source in addition to its existing musical pitch-bend role.

When a pitch-bend control is learned to a device parameter:

- incoming `-1...+1` pitch bend is mapped to normalized `0...1`
- the mapped parameter is driven live
- if transport recording/overdub is active, points are written into the matching automation lane

The actual instrument pitch-bend path remains intact, so expressive performance still works when MPE/pitch bend is enabled.

## MIDI monitor / sanity check

Settings → MIDI now includes a lightweight MIDI monitor. It shows recent decoded CoreMIDI input events so hardware like the Akai MPK Mini IV can be sanity-checked without guessing:

- Note On / Off
- CC number/value/channel
- pitch bend raw 14-bit value and normalized value
- channel pressure
- poly pressure

## MPK Mini IV preset

Added an `Akai MPK Mini IV` controller preset entry with the same common macro/pad defaults as the existing MPK Mini preset, plus notes clarifying that pitch bend can be learned as a high-resolution control source.
