# Buildfix100 — Festival/Epic Bass Agent Tone Repair

Scope: Sound Agent patch generation only. Splice, Arrangement resizing, AU hosting, recording, count-in, and metronome code were not touched.

## Problem

The prompt `Create me a Tiesto-style epic bass` was being classified as generic `bass`. The generic bass recipe used a low/mid wavetable position and a second oscillator setup that could land on a hollow/square-like timbre in Serum 2/Vital-style AU parameter space. The agent was technically touching real parameters, but the resulting tone was wrong for mainstage/progressive/epic bass.

## Fix

Added a distinct `festivalBass` sound family in the agentic translation layer. Detection covers prompts containing bass plus terms such as Tiesto/Tiësto, epic, festival, progressive, prog house, big room, EDM, trance, anthem, and mainstage.

The new recipe is saw-forward and mono:

- Osc A level high, wavetable position pushed away from the square-ish hollow area.
- Osc A unison capped low, detune kept tight.
- Osc B used as controlled reinforcement, not a detuned square stack.
- Sub level present but not overpowering.
- Filter cutoff higher than generic bass, low resonance, moderate drive/fat.
- Tight amp envelope with high sustain and short release.
- Delay/reverb effectively dry for bass.
- Macro fallback slots now describe body, grit, tight width, sub, movement, space, and output.

Stock Analog fallback was also updated so the built-in synth path makes a saw + sine progressive-house bass rather than a square/hollow one.
