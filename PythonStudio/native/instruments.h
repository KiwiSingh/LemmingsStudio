#pragma once
#include "drums.h"
struct LSAnalogParams {
    double cutoff, resonance, attack, decay, sustain, release, detune;
    float mix, gain;
    std::uint32_t osc1, osc2; // sine, triangle, saw, square
};
struct LSInstrument;
// All allocation occurs at creation. Events and rendering allocate no memory.
LS_API LSInstrument* ls_instrument_create(std::uint32_t kind, double rate,
    const LSAnalogParams* params, std::uint64_t seed) noexcept;
LS_API void ls_instrument_destroy(LSInstrument* instrument) noexcept;
// type: 0 note-off, 1 note-on, 2 pitch bend (note=range), 3 all-notes-off.
LS_API int ls_instrument_event(LSInstrument*, std::uint32_t type, int note, float value) noexcept;
LS_API int ls_instrument_process(LSInstrument*, float* output, std::uint32_t frames) noexcept;
// Deterministic comparison hook: actual Swift-generated guitar excitation.
LS_API int ls_guitar_excitation(LSInstrument*, int note, const float*, std::uint32_t count) noexcept;
