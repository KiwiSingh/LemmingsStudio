#pragma once
#include "drums.h"
// Single consumer; lifecycle calls must not overlap. No Python/audio callbacks.
struct LSCapture;
struct LSCaptureInfo {
    std::uint32_t rate, channels, capacity;
    std::uint64_t received, dropped, discontinuities;
    double endpoint_latency_seconds;
    float peak;
    std::int32_t error;
};
struct LSCaptureDevice { char id[1024]; char name[512]; };
LS_API std::uint32_t ls_capture_abi_version() noexcept;
// Packed little-endian endpoint samples; allocation-free format conversion.
LS_API int ls_capture_decode(const std::uint8_t*,std::uint32_t samples,std::uint32_t bits,std::uint32_t floating,float*) noexcept;
// Returns active device count, or negative HRESULT/error. index<0 counts only.
LS_API int ls_capture_device(int index, LSCaptureDevice*) noexcept;
LS_API LSCapture* ls_capture_open(const char* utf8_endpoint_id) noexcept;
// Deterministic packet backend exercises the exact production ring off hardware.
LS_API LSCapture* ls_capture_test_open(std::uint32_t rate,std::uint32_t channels,std::uint32_t capacity) noexcept;
LS_API int ls_capture_test_push(LSCapture*,const float* interleaved,std::uint32_t frames,std::uint32_t flags) noexcept;
LS_API int ls_capture_read(LSCapture*,float* interleaved,std::uint32_t capacity_frames) noexcept;
LS_API int ls_capture_info(LSCapture*,LSCaptureInfo*) noexcept;
// Stop joins native input thread; queued frames remain available until destroy.
LS_API void ls_capture_stop(LSCapture*) noexcept;
LS_API void ls_capture_destroy(LSCapture*) noexcept;
