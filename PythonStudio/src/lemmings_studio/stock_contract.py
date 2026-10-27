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

# DeviceFactory / StockDSPFactory dispatch, not inferred from marketing names.
EFFECT_FAMILIES={
 'Room Space':'reverb','Hybrid Space':'reverb',
 'Tempo Delay':'delay','Space Echo':'delay','Filtered Delay':'delay','Grain Echo':'delay','Vector Echo':'delay',
 'Motion Filter':'filter','Eight-Band EQ':'eq8','Dynamics Compressor':'compressor',
 'Multiband Processor':'compressor','Bus Compressor':'glue','Pitch Corrector':'tune',
 'Sample Align':'align','Drive Amp':'saturation','Drive':'saturation','Stomp Box':'saturation',
 'Tube Drive':'saturation','Saturation':'saturation','Multi-Drive':'saturation',
 'Speaker Cabinet':'cabinet','Motion Pan':'autopan','Chorus Ensemble':'chorus',
 'Phase Flange':'chorus','Frequency Shifter':'chorus','Beat Stutter':'repeat','Loop Recorder':'repeat',
 'Noise Gate':'gate','Peak Limiter':'limiter','Drum Drive Bus':'drumbuss',
 'Channel Shaper':'channel','Three-Band EQ':'eq3','Bit Crusher':'redux',
 'Noise Erode':'erosion','Tuned Resonators':'resonator','Body Resonator':'resonator',
 'Spectral Body':'resonator','Record Distortion':'vinyl','Mod Shaper':'shaper',
 'Voice Coder':'vocoder','Spectral Freeze':'character','Grain Cloud':'character',
 'FX Architect':'architect','Gain Utility':'utility',
 'LFO':'analyzer','Envelope Tracker':'analyzer','Spectrum Analyzer':'analyzer','Pitch Tuner':'analyzer',
}
MIDI_DEVICES=frozenset(['Pattern Arp','Chord Builder','Pitch Tool','Scale Mapper',
 'Velocity Mapper','Note Gate Length','Note Randomizer','Note Bounce'])
RACK_DEVICES=frozenset(['FX Rack','Instrument Layer Rack','MIDI Rack'])
BRIDGE_DEVICES=frozenset(['External FX Bridge','External Instrument Bridge','CV Instrument Bridge','CV Trigger Bridge'])
BUILTIN_DEVICES=MAPPED_INSTRUMENT_DEVICES|frozenset(['Multisampler','Simple Sampler'])

DEVICE_TRACKS={kind:'Analog Synth' for kind in ANALOG_DEVICES}
DEVICE_TRACKS.update({kind:'Drum Machine' for kind in ['Drum Matrix','Percussion Pads','Synth Clap','Synth Clang','Synth Cymbal','Synth Hat','Synth Kick','Synth Snare','Synth Tone']})
DEVICE_TRACKS.update({'Bass Synth':'LemmingBass','LemmingBass':'LemmingBass','Oscillatron':'Oscillatron','Bhangra Architect':'Bhangra Architect','2C':'2C','Bailaton':'Bailaton','Dubstep Wrangler':'Dubstep Wrangler'})
