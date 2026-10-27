"""Mac AppState.builtInInstrumentKind mapping for the original AnalogSynth aliases.

These labels use the same AnalogSynth in the reference application. They are not
claims of separate synthesis engines or of completed sampler/FM implementations.
"""
ANALOG_DEVICES=frozenset(['Subtractive Synth','Analog Drift','FM Matrix','Poly Synth',
    'Table Synth','Morph Synth','Particle Synth','Vector FM Synth','Vector Grain Synth',
    'Branch Tone','Modal Mallet','String Modeler','Electric Keys'])

# Exactly the devices AppState replaces when selecting another built-in source.
MAPPED_INSTRUMENT_DEVICES=ANALOG_DEVICES | frozenset([
    'Bass Synth','LemmingBass','Oscillatron','Bhangra Architect','2C','Bailaton',
    'Dubstep Wrangler','Drum Matrix','Percussion Pads','Synth Clap','Synth Clang',
    'Synth Cymbal','Synth Hat','Synth Kick','Synth Snare','Synth Tone'])
