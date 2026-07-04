# FX Architect buildfix 68

Adds **FX Architect**, a stock stereo transition-FX generator inspired by the stability-first stock-device philosophy seen in projects like LMMS: deterministic DSP, bounded buffers, no per-sample allocations, and useful musical presets instead of fragile placeholder devices.

Preset values:

- `0` Riser
- `1` Tonal Riser
- `2` Impact
- `3` Downlifter
- `4` Noise Sweep

Controls: Preset, Length, Intensity, Root, Sweep, Tone, Stereo, Output, and Dry/Wet.

The device is intentionally self-generating, so it can create risers/impacts on an otherwise empty track. It still works as an insert by mixing generated FX with incoming audio.
