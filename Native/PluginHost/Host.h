#pragma once
#include <stdint.h>
#if defined(_WIN32)
#define LP_API extern "C" __declspec(dllexport)
#else
#define LP_API extern "C" __attribute__((visibility("default")))
#endif
struct LPHost;
// Creation/editor/destruction run on the application's main thread. Each handle
// owns one processor: the editor, render, parameters and state all use it.
LP_API uint32_t lp_abi();
LP_API LPHost* lp_open(const char* identifier,int format,double rate,int maximum,char* error,int capacity);
LP_API void lp_close(LPHost*);
LP_API int lp_process(LPHost*,float* left,float* right,int frames,int instrument);
LP_API int lp_midi(LPHost*,uint8_t status,uint8_t a,uint8_t b);
LP_API int lp_editor(LPHost*);
LP_API void lp_hide_editor(LPHost*);
LP_API int lp_editor_visible(LPHost*);
LP_API int lp_param_count(LPHost*);
LP_API int lp_param_info(LPHost*,int index,char* identifier,int id_capacity,char* name,int name_capacity);
LP_API float lp_get(LPHost*,int index);
LP_API int lp_set(LPHost*,int index,float normalized);
LP_API int lp_state(LPHost*,void* destination,int capacity);
LP_API int lp_restore(LPHost*,const void*,int bytes);
LP_API int lp_latency(LPHost*);
LP_API int lp_is_instrument(LPHost*);
LP_API void lp_set_timeline_seconds(LPHost*, double seconds);
LP_API void lp_transport(LPHost*,double bpm,double ppq,int playing);
