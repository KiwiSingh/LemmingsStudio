#include "capture.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <string>
#include <thread>
#include <vector>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>
#include <wrl/client.h>
using Microsoft::WRL::ComPtr;
#endif
static_assert(std::atomic<std::uint64_t>::is_always_lock_free && std::atomic<float>::is_always_lock_free);
struct LSCapture {
    std::uint32_t rate=0,channels=0,capacity=0;
    std::vector<float> ring;
    std::atomic<std::uint64_t> write{0},read{0},received{0},dropped{0},discontinuities{0};
    std::atomic<float> peak{0};
    std::atomic<std::int32_t> error{0};
    std::atomic<bool> stop{false};
    double latency=0;
    bool test=false;
    std::thread thread;
    // Only the native producer writes. Publish after all packet samples are copied.
    int push(const float* data,std::uint32_t frames,std::uint32_t flags) noexcept {
        if(stop.load() || frames>capacity || (!data && !(flags&1)))return -1;
        if((flags&2) && received.load()>0)discontinuities.fetch_add(1);
        const auto w=write.load(std::memory_order_relaxed),r=read.load(std::memory_order_acquire);
        received.fetch_add(frames);
        if(frames>capacity-(w-r)) { dropped.fetch_add(frames); error.store(-2);stop.store(true);return -2; }
        float p=0;
        for(std::uint32_t f=0;f<frames;++f)for(std::uint32_t c=0;c<channels;++c){
            float value=flags&1?0:data[std::size_t(f)*channels+c];
            if(!std::isfinite(value)){value=0;error.store(-3);stop.store(true);}
            ring[((w+f)%capacity)*channels+c]=value;p=std::max(p,std::abs(value));
        }
        peak.store(p);write.store(w+frames,std::memory_order_release);return 0;
    }
};
#ifdef _WIN32
namespace {
struct Apartment { HRESULT hr=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED); ~Apartment(){if(SUCCEEDED(hr))CoUninitialize();} };
struct Handle { HANDLE h=CreateEventW(nullptr,FALSE,FALSE,nullptr);~Handle(){if(h)CloseHandle(h);} };
struct Priority { DWORD index=0; HANDLE h=AvSetMmThreadCharacteristicsW(L"Audio",&index);~Priority(){if(h)AvRevertMmThreadCharacteristics(h);} };
struct Format { WAVEFORMATEX* value=nullptr;~Format(){CoTaskMemFree(value);} };
std::wstring wide(const char* text){
    if(!text || !*text)return {};
    int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text,-1,nullptr,0);
    if(n<=0)throw E_INVALIDARG;
    std::wstring s(n,L'\0');MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text,-1,s.data(),n);s.resize(n-1);return s;
}
void utf8(const wchar_t* value,char* out,int capacity){
    if(!value || !WideCharToMultiByte(CP_UTF8,0,value,-1,out,capacity,nullptr,nullptr))throw E_INVALIDARG;
}
void check(HRESULT hr){if(FAILED(hr))throw hr;}
void capture(LSCapture* p,std::wstring endpoint,std::atomic<int>* ready) noexcept {
    bool published=false;
    try {
        Apartment apartment;check(apartment.hr);
        ComPtr<IMMDeviceEnumerator> enumerator;
        check(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,IID_PPV_ARGS(&enumerator)));
        ComPtr<IMMDevice> device;
        if(endpoint.empty())check(enumerator->GetDefaultAudioEndpoint(eCapture,eConsole,&device));
        else check(enumerator->GetDevice(endpoint.c_str(),&device));
        ComPtr<IAudioClient> client;check(device->Activate(__uuidof(IAudioClient),CLSCTX_ALL,nullptr,&client));
        Format format;check(client->GetMixFormat(&format.value));auto* f=format.value;
        bool floating=f->wFormatTag==WAVE_FORMAT_IEEE_FLOAT;
        bool pcm=f->wFormatTag==WAVE_FORMAT_PCM;
        if(f->wFormatTag==WAVE_FORMAT_EXTENSIBLE && f->cbSize>=22){
            auto* ext=reinterpret_cast<WAVEFORMATEXTENSIBLE*>(f);
            const GUID floatSubtype={STATIC_KSDATAFORMAT_SUBTYPE_IEEE_FLOAT};
            const GUID pcmSubtype={STATIC_KSDATAFORMAT_SUBTYPE_PCM};
            floating=IsEqualGUID(ext->SubFormat,floatSubtype);
            pcm=IsEqualGUID(ext->SubFormat,pcmSubtype);
        }
        if(!f->nChannels || f->nChannels>32 || f->nSamplesPerSec<8000 || f->nSamplesPerSec>192000 ||
           (!floating && !pcm) || (floating && f->wBitsPerSample!=32) ||
           (pcm && f->wBitsPerSample!=16 && f->wBitsPerSample!=24 && f->wBitsPerSample!=32) ||
           f->nBlockAlign!=f->nChannels*(f->wBitsPerSample/8))throw AUDCLNT_E_UNSUPPORTED_FORMAT;
        p->rate=f->nSamplesPerSec;p->channels=f->nChannels;p->capacity=p->rate*8;
        p->ring.resize(std::size_t(p->capacity)*p->channels);
        Handle event;if(!event.h)throw E_OUTOFMEMORY;
        check(client->Initialize(AUDCLNT_SHAREMODE_SHARED,AUDCLNT_STREAMFLAGS_EVENTCALLBACK,0,0,f,nullptr));
        check(client->SetEventHandle(event.h));
        REFERENCE_TIME latency=0;check(client->GetStreamLatency(&latency));p->latency=double(latency)/10000000.;
        UINT32 buffer=0;check(client->GetBufferSize(&buffer));
        std::vector<float> packet(std::size_t(buffer)*p->channels);
        ComPtr<IAudioCaptureClient> input;check(client->GetService(IID_PPV_ARGS(&input)));
        Priority priority;
        check(client->Start());published=true;ready->store(1,std::memory_order_release);
        try {
            while(!p->stop.load()){
                auto wait=WaitForSingleObject(event.h,100);
                if(wait==WAIT_TIMEOUT)continue;
                if(wait!=WAIT_OBJECT_0)throw E_FAIL;
                UINT32 size=0;check(input->GetNextPacketSize(&size));
                while(size && !p->stop.load()){
                    BYTE* bytes=nullptr;UINT32 frames=0;DWORD flags=0;
                    check(input->GetBuffer(&bytes,&frames,&flags,nullptr,nullptr));
                    if(frames>buffer){input->ReleaseBuffer(frames);throw E_UNEXPECTED;}
                    if(!(flags&AUDCLNT_BUFFERFLAGS_SILENT)){
                        if(ls_capture_decode(bytes,frames*p->channels,f->wBitsPerSample,floating?1:0,packet.data())<0){
                            input->ReleaseBuffer(frames);throw AUDCLNT_E_UNSUPPORTED_FORMAT;
                        }
                    }
                    p->push(packet.data(),frames,(flags&AUDCLNT_BUFFERFLAGS_SILENT?1:0)|(flags&AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY?2:0));
                    check(input->ReleaseBuffer(frames));check(input->GetNextPacketSize(&size));
                }
            }
        } catch(...) {client->Stop();throw;}
        check(client->Stop());
    } catch(HRESULT hr){p->error.store(static_cast<std::int32_t>(hr));}
      catch(...){p->error.store(-4);}
    p->stop.store(true);
    if(!published)ready->store(-1,std::memory_order_release);
}
}
#endif
std::uint32_t ls_capture_abi_version() noexcept{return 1;}
int ls_capture_decode(const std::uint8_t* bytes,std::uint32_t samples,std::uint32_t bits,std::uint32_t floating,float* out) noexcept {
    if(!bytes || !out || samples>65536*32 || floating>1 || (floating && bits!=32) || (!floating && bits!=16 && bits!=24 && bits!=32))return -1;
    const unsigned width=bits/8;
    for(std::uint32_t i=0;i<samples;++i){
        float value=0;const auto* b=bytes+std::size_t(i)*width;
        if(floating)std::memcpy(&value,b,4);
        else if(width==2){std::int16_t v;std::memcpy(&v,b,2);value=v/32768.f;}
        else if(width==3){std::int32_t v=b[0]|(std::int32_t(b[1])<<8)|(std::int32_t(b[2])<<16);if(v&0x800000)v-=16777216;value=v/8388608.f;}
        else {std::int32_t v;std::memcpy(&v,b,4);value=float(double(v)/2147483648.);}
        out[i]=value;
    }
    return 0;
}
int ls_capture_device(int index,LSCaptureDevice* out) noexcept {
#ifdef _WIN32
    try {
        Apartment apartment;check(apartment.hr);
        ComPtr<IMMDeviceEnumerator> enumerator;
        check(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,IID_PPV_ARGS(&enumerator)));
        ComPtr<IMMDeviceCollection> devices;check(enumerator->EnumAudioEndpoints(eCapture,DEVICE_STATE_ACTIVE,&devices));
        UINT count=0;check(devices->GetCount(&count));if(index<0)return int(count);
        if(!out || unsigned(index)>=count)return -1;
        *out={};ComPtr<IMMDevice> device;check(devices->Item(index,&device));
        LPWSTR id=nullptr;check(device->GetId(&id));
        try{utf8(id,out->id,sizeof(out->id));}catch(...){CoTaskMemFree(id);throw;}CoTaskMemFree(id);
        ComPtr<IPropertyStore> properties;check(device->OpenPropertyStore(STGM_READ,&properties));
        PROPVARIANT name;PropVariantInit(&name);check(properties->GetValue(PKEY_Device_FriendlyName,&name));
        try{if(name.vt!=VT_LPWSTR)throw E_FAIL;utf8(name.pwszVal,out->name,sizeof(out->name));}
        catch(...){PropVariantClear(&name);throw;}PropVariantClear(&name);return int(count);
    } catch(HRESULT hr){return static_cast<int>(hr);}catch(...){return -4;}
#else
    (void)index;(void)out;return -5;
#endif
}
LSCapture* ls_capture_open(const char* endpoint) noexcept {
#ifdef _WIN32
    try {
        auto p=std::make_unique<LSCapture>();std::atomic<int> ready{0};
        p->thread=std::thread(capture,p.get(),wide(endpoint),&ready);
        // Initialization is called on a background application job, never Qt/audio.
        while(ready.load(std::memory_order_acquire)==0)std::this_thread::sleep_for(std::chrono::milliseconds(1));
        if(ready.load()<0){p->thread.join();return nullptr;}
        return p.release();
    }catch(...){return nullptr;}
#else
    (void)endpoint;return nullptr;
#endif
}
LSCapture* ls_capture_test_open(std::uint32_t rate,std::uint32_t channels,std::uint32_t capacity) noexcept {
    if(rate<8000 || rate>192000 || !channels || channels>32 || !capacity || capacity>rate*8)return nullptr;
    try{auto p=std::make_unique<LSCapture>();p->rate=rate;p->channels=channels;p->capacity=capacity;
        p->ring.resize(std::size_t(capacity)*channels);p->test=true;return p.release();}catch(...){return nullptr;}
}
int ls_capture_test_push(LSCapture* p,const float* data,std::uint32_t frames,std::uint32_t flags) noexcept {
    if(!p || !p->test || flags>3)return -1;
    return p->push(data,frames,flags);
}
int ls_capture_read(LSCapture* p,float* out,std::uint32_t capacity) noexcept {
    if(!p || !out || capacity>65536)return -1;
    auto r=p->read.load(std::memory_order_relaxed),w=p->write.load(std::memory_order_acquire);
    auto frames=std::min<std::uint64_t>(capacity,w-r);
    for(std::uint64_t f=0;f<frames;++f)std::memcpy(out+f*p->channels,p->ring.data()+((r+f)%p->capacity)*p->channels,p->channels*sizeof(float));
    p->read.store(r+frames,std::memory_order_release);return int(frames);
}
int ls_capture_info(LSCapture* p,LSCaptureInfo* out) noexcept {
    if(!p || !out)return -1;
    *out={p->rate,p->channels,p->capacity,p->received.load(),p->dropped.load(),p->discontinuities.load(),p->latency,p->peak.load(),p->error.load()};return 0;
}
void ls_capture_stop(LSCapture* p) noexcept {if(p){p->stop.store(true);if(p->thread.joinable())p->thread.join();}}
void ls_capture_destroy(LSCapture* p) noexcept{ls_capture_stop(p);delete p;}
