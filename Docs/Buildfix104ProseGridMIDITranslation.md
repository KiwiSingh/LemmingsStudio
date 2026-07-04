# Buildfix104 — Prose/Grid MIDI Translation

Scope: Assistant/agent MIDI translation only. Splice, AU hosting, metronome/count-in, Arrangement resize, and sound-design parameter mapping are intentionally untouched.

## Problem

The assistant could fall back from invalid JSON to a deterministic note generator, but it could not consume useful musical prose from a model. Responses such as a Perplexity/Claude-style 4-bar grid:

```text
Bar 1: C2 - - - | E2 - G2 - | C2 - - - | G2 - E2 -
```

were ignored and replaced by a generic fallback phrase.

## Fix

`AIAssistant.naturalLanguageFallback` now first tries to parse explicit note grids/tables from the prompt plus model response before generating its own fallback notes.

Supported input patterns include:

- `Bar 1: C2 - - - | E2 - G2 - ...`
- Markdown table rows such as `| **Bar 1** | C2 | – | – | ... |`
- Unicode dashes and accidentals (`–`, `—`, `♯`, `♭`)
- Notes with octaves (`C2`, `F#3`, `Bb1`)
- 16th-note or other equal-subdivision grids; timing is inferred from the number of cells in the bar

Dash cells are treated as holds of the previous note, which matches common DAW/prose grid notation. Hard rest tokens such as `rest`, `r`, or `0` explicitly close the previous note.

Duplicate bar descriptions are ignored after the first parsed instance, so a model can include both a code block and a table without doubling the MIDI.

## Result

If a model returns prose like a 4-bar C-major bass melody, LemmingsStudio converts those notes into real `add_notes` ops instead of throwing `Couldn't parse the assistant's plan` or replacing the musical content with a generic deterministic bassline.
