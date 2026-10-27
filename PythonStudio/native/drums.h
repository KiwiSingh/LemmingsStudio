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
struct LSDrumKit;
LS_API LSDrumKit* ls_kit_create(double rate,const LSDrumParams*) noexcept;
LS_API void ls_kit_destroy(LSDrumKit*) noexcept;
LS_API int ls_kit_event(LSDrumKit*,std::uint32_t type,int note,float velocity) noexcept;
LS_API int ls_kit_set(LSDrumKit*,const char*,double) noexcept;
LS_API int ls_kit_process(LSDrumKit*,float*,std::uint32_t) noexcept;
struct LSSampleMixer;
LS_API LSSampleMixer* ls_samples_create(std::uint32_t max_voices) noexcept;
LS_API void ls_samples_destroy(LSSampleMixer*) noexcept;
LS_API int ls_samples_load(LSSampleMixer*,int note,const float*,std::uint32_t count,float level) noexcept;
LS_API int ls_samples_event(LSSampleMixer*,std::uint32_t type,int note,float velocity) noexcept;
LS_API int ls_samples_process(LSSampleMixer*,float* mono,std::uint32_t frames) noexcept;
// Worker-only warp preparation; output length is count*ratio+2048 (count<=4096: count).
LS_API int ls_warp(const float*,std::uint32_t,double,std::uint32_t,float*,std::uint32_t) noexcept;
LS_API int ls_metronome(const double*,std::uint32_t,double,double,double,std::uint32_t,float,float*) noexcept;
