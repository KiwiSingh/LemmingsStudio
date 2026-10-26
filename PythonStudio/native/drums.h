#pragma once
#include <cstdint>
#if defined(_WIN32)
#define LS_API extern "C" __declspec(dllexport)
#else
#define LS_API extern "C" __attribute__((visibility("default")))
#endif
// Versioned C ABI. No exceptions, ownership transfer or Python callbacks.
struct LSDrumParams { double tune, decay, tone; float drive, level, velocity; };
LS_API std::uint32_t ls_audio_abi_version() noexcept;
// Offline one-shot parity renderer. Not the streaming audio graph API.
// Voice order matches Swift DrumVoiceID; returns 0 or -1 for invalid input.
LS_API int ls_render_drum(std::uint32_t voice, double sample_rate,
                         const LSDrumParams* params, float* output,
                         std::uint32_t frames) noexcept;

struct LSDrumEvent { std::uint64_t frame; std::uint32_t voice; float velocity; };
LS_API int ls_render_drum_kit(double sample_rate, const LSDrumParams* params,
                             const LSDrumEvent* events, std::uint32_t count,
                             float master, float* output, std::uint32_t frames) noexcept;
// Offline master processing; interleaved stereo, original Mac limiter defaults/units.
LS_API int ls_apply_limiter(float* stereo, std::uint32_t frames, double rate,
                              const double* parameters) noexcept;
