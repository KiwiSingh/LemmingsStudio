// Faithful port of Sources/LemmingsStudio/Instruments/Drums.swift: DrumVoice.
#include "drums.h"
#include <cmath>
#include <initializer_list>
#include <array>
#include <algorithm>
#include <numbers>
namespace {
class DrumVoice {
    double sr, t = 0, phase = 0;
    bool active = true;
    std::uint32_t id;
    LSDrumParams p;
    float noiseLP = 0;
    std::uint64_t rng = 0x9E3779B97F4A7C15ULL;
    float noise() noexcept {
        rng = rng * 6364136223846793005ULL + 1442695040888963407ULL;
        const double unit = double(rng >> 33) / double((std::uint64_t(1) << 31)-1);
        return float(unit * 2.0 - 1.0);
    }
    float env(double tau) const noexcept { return float(std::exp(-t/(tau*p.decay))); }
public:
    DrumVoice(std::uint32_t voice=0, double rate=48000, LSDrumParams params={1.,1.,1.,1.f,1.f,.8f}): sr(rate), id(voice), p(params) {}
    void stop() noexcept { active = false; }
    void trigger(std::uint32_t voice, double rate, LSDrumParams params) noexcept {
        id=voice; sr=rate; p=params; t=0; phase=0; noiseLP=0; active=true;
    }
    float render() noexcept {
        if (!active) return 0;
        const double dt = 1.0/sr, pi = std::numbers::pi;
        float s = 0;
        switch (id) {
        case 0: {
            const double f0 = 52.0*p.tune, pitchEnv = 1.0+6.0*std::exp(-t/0.012);
            phase += 2*pi*f0*pitchEnv*dt;
            s = float(std::sin(phase))*env(0.16);
            s += noise()*env(0.004)*0.6f;
            break;
        }
        case 1:
            phase += 2*pi*(44.0*p.tune)*(1+2*std::exp(-t/0.03))*dt;
            s = float(std::sin(phase))*env(0.5);
            s = std::tanh(s*1.6f*p.drive);
            break;
        case 2: {
            const float body = float(std::sin(2*pi*190*p.tune*t))*env(0.09);
            const float n = noise()*env(0.12);
            s = body*0.5f+n*0.7f;
            break;
        }
        case 3: {
            float c = 0;
            for (double b : {0.0, 0.009, 0.018}) if (t >= b) c += noise()*float(std::exp(-(t-b)/0.012));
            c += noise()*env(0.12)*0.5f;
            s = c*0.6f;
            break;
        }
        case 4: {
            const float tone = float(std::sin(2*pi*1700*t));
            const float n = noise();
            s = (tone+n*0.5f)*env(0.012);
            break;
        }
        case 5: case 6:
            noiseLP = noiseLP*0.5f+noise()*0.5f;
            s = (noise()-noiseLP)*env((id == 5 ? 0.025 : 0.35)*p.tone);
            break;
        case 7:
            phase += 2*pi*(120.0*p.tune)*(1+1.5*std::exp(-t/0.04))*dt;
            s = float(std::sin(phase))*env(0.22);
            break;
        case 8: {
            float r = 0;
            for (double h : {1.0, 1.34, 1.71, 2.4}) r += float(std::sin(2*pi*520*h*t));
            s = (r*0.25f+noise()*0.3f)*env(0.5*p.tone);
            break;
        }
        case 9:
            noiseLP = noiseLP*0.3f+noise()*0.7f;
            s = (noise()-noiseLP*0.5f)*env(0.8*p.tone);
            break;
        }
        s = std::tanh(s*p.drive)*p.level*p.velocity;
        t += dt;
        if ((id == 5 && t > 0.12*p.decay*p.tone) ||
            (id == 6 && t > 0.38*p.decay*p.tone) ||
            (id == 8 && t > 0.55*p.decay*p.tone) ||
            (id == 9 && t > 0.65*p.decay*p.tone)) active = false;
        if (t > 1.25 || (env(0.35) < 1e-4f && t > 0.1)) active = false;
        return s;
    }
};
}
std::uint32_t ls_audio_abi_version() noexcept { return 1; }
int ls_render_drum(std::uint32_t voice, double rate, const LSDrumParams* p,
                   float* output, std::uint32_t frames) noexcept {
    if (!p || !output || voice > 9 || !std::isfinite(rate) || rate < 8000 || rate > 192000) return -1;
    if (!std::isfinite(p->tune) || p->tune <= 0 || p->tune > 16 ||
        !std::isfinite(p->decay) || p->decay <= 0 || p->decay > 16 ||
        !std::isfinite(p->tone) || p->tone <= 0 || p->tone > 16 ||
        !std::isfinite(p->drive) || p->drive < 0 || p->drive > 32 ||
        !std::isfinite(p->level) || p->level < 0 || p->level > 4 ||
        !std::isfinite(p->velocity) || p->velocity < 0 || p->velocity > 1) return -1;
    DrumVoice state(voice, rate, *p);
    for (std::uint32_t i = 0; i < frames; ++i) output[i] = state.render();
    return 0;
}

int ls_render_drum_kit(double rate, const LSDrumParams* params,
                       const LSDrumEvent* events, std::uint32_t count,
                       float master, float* output, std::uint32_t frames) noexcept {
    if (!params || !output || (count && !events) || !std::isfinite(rate) || rate < 8000 || rate > 192000 ||
        !std::isfinite(master) || master < 0 || master > 1.5f) return -1;
    float probe;
    for (std::uint32_t v=0; v<10; ++v) if (ls_render_drum(v,rate,params+v,&probe,0)) return -1;
    for (std::uint32_t i=0; i<count; ++i) {
        if (events[i].voice>9 || !std::isfinite(events[i].velocity) || events[i].velocity<0 || events[i].velocity>1 ||
            (i && events[i].frame<events[i-1].frame)) return -1;
    }
    std::array<DrumVoice,24> voices;
    for (auto& voice:voices) voice.stop();
    std::uint32_t event=0, next=0;
    for (std::uint32_t frame=0; frame<frames; ++frame) {
        while (event<count && events[event].frame==frame) {
            const auto& hit=events[event++];
            auto p=params[hit.voice]; p.velocity=hit.velocity;
            voices[next].trigger(hit.voice,rate,p); next=(next+1)%voices.size();
        }
        float sum=0;
        for (auto& voice:voices) sum+=voice.render();
        output[frame]=std::tanh(sum*.8f)*master;
    }
    return 0;
}

int ls_apply_limiter(float* stereo, std::uint32_t frames, double rate, const double* p) noexcept {
    if (!stereo || !p || !std::isfinite(rate) || rate<8000 || rate>192000) return -1;
    for (int i=0;i<6;++i) if (!std::isfinite(p[i])) return -1;
    if (p[0]<-60 || p[0]>6 || p[1]<-60 || p[1]>6 || p[2]<1 || p[2]>5000 || p[3]<0 || p[3]>100 || p[4]<0 || p[4]>1 || p[5]<-60 || p[5]>24) return -1;
    std::array<float,8192> left{},right{};
    const auto count=std::max(1,std::min(8192,int(rate*std::max(0.,p[3])*.001)));
    const float ceiling=float(std::pow(10.,p[0]/20.)),threshold=float(std::pow(10.,p[1]/20.)),out=float(std::pow(10.,p[5]/20.));
    const float release=float(std::exp(-1./(std::max(1.,p[2])*.001*rate)));
    const float drive=std::max(.0001f,ceiling/std::max(.0001f,threshold)),blend=float(p[4]);
    float gain=1.;int index=0;
    for (std::uint32_t i=0;i<frames;++i) {
        const float inL=stereo[2*i],inR=stereo[2*i+1],delayedL=left[index],delayedR=right[index];
        left[index]=inL;right[index]=inR;index=(index+1)%count;
        const float peak=std::max(std::abs(inL),std::abs(inR))*drive;
        const float target=peak>ceiling ? ceiling/std::max(peak,.000001f) : 1.f;
        gain=target<gain ? target : target+release*(gain-target);
        float l=delayedL*drive*gain,r=delayedR*drive*gain;
        if(blend>0){const float cl=std::tanh(l/std::max(.0001f,ceiling))*ceiling,cr=std::tanh(r/std::max(.0001f,ceiling))*ceiling;l=l*(1-blend)+cl*blend;r=r*(1-blend)+cr*blend;}
        stereo[2*i]=std::max(-ceiling,std::min(ceiling,l))*out;stereo[2*i+1]=std::max(-ceiling,std::min(ceiling,r))*out;
    }
    return 0;
}

#include <string_view>
#include <vector>
#include <memory>
struct LSDrumKit {
 double rate;std::array<DrumVoice,24> voices;std::array<LSDrumParams,10> params;float master=1;unsigned next=0;
 LSDrumKit(double sr,const LSDrumParams* p):rate(sr){std::copy_n(p,10,params.begin());for(auto& v:voices)v.stop();}
};
LSDrumKit* ls_kit_create(double rate,const LSDrumParams* params) noexcept {
 if(!params||!std::isfinite(rate)||rate<8000||rate>192000)return nullptr;float probe;
 for(unsigned i=0;i<10;++i)if(ls_render_drum(i,rate,params+i,&probe,0))return nullptr;
 try{return new LSDrumKit(rate,params);}catch(...){return nullptr;}
}
void ls_kit_destroy(LSDrumKit* kit) noexcept {delete kit;}
int ls_kit_event(LSDrumKit* kit,std::uint32_t type,int note,float velocity) noexcept {
 if(!kit||type>3||note<0||note>127||!std::isfinite(velocity)||velocity<0||velocity>1)return -1;
 if(type==3){for(auto& v:kit->voices)v.stop();return 0;}
 if(type!=1)return 0;constexpr int notes[]={36,35,38,39,37,42,46,45,51,49};
 for(unsigned i=0;i<10;++i)if(note==notes[i]){auto p=kit->params[i];p.velocity=velocity;kit->voices[kit->next].trigger(i,kit->rate,p);kit->next=(kit->next+1)%24;break;}return 0;
}
int ls_kit_set(LSDrumKit* kit,const char* id,double value) noexcept {
 if(!kit||!id||!std::isfinite(value))return -1;std::string_view key=id;
 if(key=="master"){if(value<0||value>1.5)return -1;kit->master=float(value);return 0;}
 if(key.size()<3||key[0]<'0'||key[0]>'9'||key[1]!='_')return -1;auto& p=kit->params[key[0]-'0'];key.remove_prefix(2);
 if(key=="tune"&&value>=.5&&value<=2)p.tune=value;else if(key=="decay"&&value>=.2&&value<=3)p.decay=value;else if(key=="level"&&value>=0&&value<=1.5)p.level=float(value);else return -1;return 0;
}
int ls_kit_process(LSDrumKit* kit,float* out,std::uint32_t frames) noexcept {
 if(!kit||!out||frames>65536)return -1;
 for(unsigned i=0;i<frames;++i){float sum=0;for(auto& voice:kit->voices)sum+=voice.render();out[i]=std::tanh(sum*.8f)*kit->master;}return 0;
}
struct LSSampleMixer {
 struct Layer {std::vector<float> samples;float level=1;};
 struct Voice {int note;std::uint32_t index;float velocity;};
 std::array<Layer,128> layers;std::array<Voice,48> voices{};unsigned count=0,limit;
 explicit LSSampleMixer(unsigned n):limit(n){}
};
LSSampleMixer* ls_samples_create(std::uint32_t max) noexcept {if(!max||max>48)return nullptr;try{return new LSSampleMixer(max);}catch(...){return nullptr;}}
void ls_samples_destroy(LSSampleMixer* p) noexcept {delete p;}
int ls_samples_load(LSSampleMixer* p,int note,const float* data,std::uint32_t count,float level) noexcept {
 if(!p||p->count||note<0||note>127||!data||count>192000*600||!std::isfinite(level)||level<0||level>1)return -1;
 for(unsigned i=0;i<count;++i)if(!std::isfinite(data[i]))return -1;
 try{p->layers[note].samples.assign(data,data+count);p->layers[note].level=level;return 0;}catch(...){return -1;}
}
int ls_samples_event(LSSampleMixer* p,std::uint32_t type,int note,float velocity) noexcept {
 if(!p||note<0||note>127||type>3||!std::isfinite(velocity)||velocity<0||velocity>1)return -1;
 if(type==3){p->count=0;return 0;}if(type!=1||p->layers[note].samples.empty())return 0;
 if(p->count==p->limit){std::move(p->voices.begin()+1,p->voices.begin()+p->count,p->voices.begin());--p->count;}
 p->voices[p->count++]={note,0,velocity*p->layers[note].level};return 0;
}
int ls_samples_process(LSSampleMixer* p,float* mono,std::uint32_t frames) noexcept {
 if(!p||!mono||frames>65536)return -1;if(!p->count)return 0;
 for(unsigned i=0;i<frames;++i){float sum=0;for(unsigned j=0;j<p->count;++j){auto& v=p->voices[j];auto& samples=p->layers[v.note].samples;if(v.index<samples.size())sum+=samples[v.index++]*v.velocity;}mono[i]=std::tanh(mono[i]+sum);}
 unsigned keep=0;for(unsigned i=0;i<p->count;++i)if(p->voices[i].index<p->layers[p->voices[i].note].samples.size())p->voices[keep++]=p->voices[i];p->count=keep;return 0;
}
