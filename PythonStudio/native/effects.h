#pragma once
#include "drums.h"
struct LSParameter { const char* id; double value; };
struct LSEffect;
// Instance state survives blocks; configuration/allocation happens off callback.
LS_API LSEffect* ls_effect_create(const char* family, double rate, double tempo,
    const LSParameter*, std::uint32_t count) noexcept;
LS_API void ls_effect_destroy(LSEffect*) noexcept;
LS_API int ls_effect_set(LSEffect*,const char*,double) noexcept;
LS_API int ls_effect_process(LSEffect*,float* stereo,std::uint32_t frames,const float* sidechain) noexcept;
LS_API int ls_effect_reset(LSEffect*) noexcept;
LS_API int ls_effect_tempo(LSEffect*,double) noexcept;
LS_API int ls_effect_get(LSEffect*,const char*,double*) noexcept;
