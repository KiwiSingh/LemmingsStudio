// Ports of Instruments.swift / DSP.swift. Preserve baseline behavior, including
// ADSR retrigger level and Karplus-Strong's per-sample early-stop rule.
#include "instruments.h"
#include <array>
#include <vector>
#include <algorithm>
#include <cmath>
#include <numbers>
#include <new>
namespace {
constexpr double pi=std::numbers::pi;
double frequency(int note) {return 440.*std::pow(2.,double(note-69)/12.);}
struct Oscillator {
    double phase=0.;
    double blep(double t,double dt) const {
        if(t<dt){const double x=t/dt;return x+x-x*x-1.;}
        if(t>1.-dt){const double x=(t-1.)/dt;return x*x+x+x+1.;}
        return 0.;
    }
    float next(double hz,double rate,std::uint32_t wave) {
        const double dt=hz/rate;double value;
        switch(wave){
        case 0:value=std::sin(2.*pi*phase);break;
        case 1:value=2.*std::abs(2.*(phase-std::floor(phase+.5)))-1.;break;
        case 2:value=2.*phase-1.;value-=blep(phase,dt);break;
        default:value=phase<.5 ? 1. : -1.;value+=blep(phase,dt);value-=blep(phase+.5-std::floor(phase+.5),dt);break;
        }
        phase+=dt;if(phase>=1.)phase-=1.;return float(value);
    }
};
struct Envelope {
    int stage=0;double level=0.;
    float next(const LSAnalogParams& p,double rate){
        switch(stage){
        case 0:level=0.;break;
        case 1:level+=1./std::max(p.attack*rate,1.);if(level>=1.){level=1.;stage=2;}break;
        case 2:level-=(1.-p.sustain)/std::max(p.decay*rate,1.);if(level<=p.sustain){level=p.sustain;stage=3;}break;
        case 3:level=p.sustain;break;
        case 4:level-=p.sustain/std::max(p.release*rate,1.);if(level<=0.){level=0.;stage=0;}break;
        }
        return float(level);
    }
};
struct Filter {
    double one=0.,two=0.;
    float process(float input,const LSAnalogParams& p,double rate){
        const double fc=std::min(std::max(p.cutoff,20.),rate*.45),g=std::tan(pi*fc/rate),k=2.-1.98*std::min(std::max(p.resonance,0.),1.);
        const double a1=1./(1.+g*(g+k)),a2=g*a1,a3=g*a2,v0=double(input),v3=v0-two,v1=a1*one+a2*v3,v2=two+a2*one+a3*v3;
        one=2.*v1-one;two=2.*v2-two;return float(v2);
    }
};
struct Voice {int note=-1;float velocity=1.;Oscillator first,second;Envelope env;Filter filter;};
struct String {
    std::vector<float> buffer;std::uint32_t index=0,length=2;bool active=false;float damping=.996f;
    float next(){
        if(!active)return 0.;const float current=buffer[index];const auto next=(index+1)%length;
        const float averaged=damping*.5f*(current+buffer[next]);buffer[index]=averaged;index=next;
        if(std::abs(averaged)<1e-5f)active=false;return current;
    }
};
}
struct LSInstrument {
    std::uint32_t kind;double rate,bend=0.;LSAnalogParams params;
    std::array<Voice,16> voices;
    std::array<String,128> strings;
    std::uint64_t rng;
    LSInstrument(std::uint32_t k,double sr,const LSAnalogParams& p,std::uint64_t seed):kind(k),rate(sr),params(p),rng(seed){
        if(kind==1)for(auto& s:strings)s.buffer.resize(std::max(2,int(rate/frequency(0))));
    }
    float noise(){rng=rng*6364136223846793005ULL+1442695040888963407ULL;return float(double(rng>>33)/double((std::uint64_t(1)<<31)-1)*2.-1.);}
    int event(std::uint32_t type,int note,float value){
        if(type==2){if(kind==0)bend=double(std::clamp(value,-1.f,1.f))*double(std::max(1,note));return 0;}
        if(kind==0){
            if(type==1){auto it=std::find_if(voices.begin(),voices.end(),[](const Voice& v){return v.env.stage==0;});if(it==voices.end())it=std::min_element(voices.begin(),voices.end(),[](const Voice& a,const Voice& b){return a.note<b.note;});
                it->note=note;it->velocity=value;it->first.phase=it->second.phase=0.;it->filter={};it->env.stage=1;
            }else for(auto& v:voices)if((type==3||v.note==note)&&v.env.stage!=0)v.env.stage=4;
        }else if(type==1){auto& s=strings[note];s.length=std::max(2,int(rate/std::max(frequency(note),1.)));s.index=0;s.active=true;s.damping=.996f;for(std::uint32_t i=0;i<s.length;++i)s.buffer[i]=noise()*std::max(.2f,value);
        }else for(int n=0;n<128;++n)if(type==3||n==note)strings[n].damping=.90f;
        return 0;
    }
    void process(float* out,std::uint32_t frames){
        std::fill_n(out,frames,0.f);
        if(kind==0){const double detune=std::pow(2.,params.detune/1200.);
            for(auto& v:voices)if(v.env.stage!=0){const double hz=frequency(v.note)*std::pow(2.,bend/12.);
                for(std::uint32_t i=0;i<frames;++i){const float a=v.first.next(hz,rate,params.osc1),b=v.second.next(hz*detune,rate,params.osc2)*params.mix;float s=(a+b)/(1.f+params.mix);s=v.filter.process(s,params,rate);s*=v.env.next(params,rate)*v.velocity*params.gain;out[i]+=s;}
            }
            for(std::uint32_t i=0;i<frames;++i){const float x=out[i],x2=x*x;out[i]=x*(27.f+x2)/(27.f+9.f*x2);}
        }else for(auto& s:strings)if(s.active)for(std::uint32_t i=0;i<frames;++i)out[i]+=s.next()*.6f;
    }
};
LSInstrument* ls_instrument_create(std::uint32_t kind,double rate,const LSAnalogParams* p,std::uint64_t seed) noexcept {
    if(kind>1||!p||!std::isfinite(rate)||rate<8000||rate>192000)return nullptr;
    for(double v:{p->cutoff,p->resonance,p->attack,p->decay,p->sustain,p->release,p->detune,double(p->mix),double(p->gain)})if(!std::isfinite(v))return nullptr;
    if(p->cutoff<20||p->cutoff>24000||p->resonance<0||p->resonance>1||p->attack<0||p->attack>10||p->decay<0||p->decay>10||p->sustain<0||p->sustain>1||p->release<0||p->release>10||std::abs(p->detune)>1200||p->mix<0||p->mix>1||p->gain<0||p->gain>1||p->osc1>3||p->osc2>3)return nullptr;
    try{return new LSInstrument(kind,rate,*p,seed);}catch(...){return nullptr;}
}
void ls_instrument_destroy(LSInstrument* p) noexcept {delete p;}
int ls_instrument_event(LSInstrument* p,std::uint32_t type,int note,float value) noexcept {
    if(!p||type>3||!std::isfinite(value))return -1;
    if(type==2){if(note<1||note>96||value<-1||value>1)return -1;}
    else if(note<0||note>127||value<0||value>1)return -1;
    return p->event(type,note,value);
}
int ls_instrument_process(LSInstrument* p,float* out,std::uint32_t frames) noexcept {if(!p||!out||frames>65536)return -1;p->process(out,frames);return 0;}
int ls_guitar_excitation(LSInstrument* p,int note,const float* data,std::uint32_t count) noexcept {
    if(!p||p->kind!=1||note<0||note>127||!data||count!=std::uint32_t(std::max(2,int(p->rate/frequency(note)))))return -1;
    for(std::uint32_t i=0;i<count;++i)if(!std::isfinite(data[i])||std::abs(data[i])>1)return -1;
    auto& s=p->strings[note];s.length=count;s.index=0;s.active=true;s.damping=.996f;std::copy_n(data,count,s.buffer.begin());return 0;
}
