// Ports of Instruments.swift / DSP.swift. Preserve baseline behavior, including
// ADSR retrigger level and Karplus-Strong's per-sample early-stop rule.
#include "instruments.h"
#include "effects.h"
#include <memory>
#include <map>
#include <string>
#include <string_view>
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
struct Voice {int note=-1;float velocity=1.;Oscillator first,second,third,sub;Envelope env;Filter filter;LSAnalogParams captured{};float click=0;};
struct Hit {std::array<double,3> phase{},freq{};std::array<float,3> amp{};int size=0;float decay=1,env=1,noiseAmount=0,noiseEnv=1,noiseDecay=1;bool alive()const{return env>1e-4f||noiseEnv>1e-4f;}};
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
    std::uint64_t rng;int voiceCount=16,hitCount=0;double shapePhase=0;
    std::map<std::string,double,std::less<>> extra;
    std::array<Hit,32> hits{};
    std::unique_ptr<LSInstrument> tumbi,reed;std::vector<float> scratch;
    double get(const char* key,double fallback=0)const{auto it=extra.find(key);return it==extra.end()?fallback:it->second;}
    LSInstrument(std::uint32_t k,double sr,const LSAnalogParams& p,std::uint64_t seed):kind(k),rate(sr),params(p),rng(seed){
        for(auto pair: {std::pair{"cutoff",p.cutoff},{"resonance",p.resonance},{"attack",p.attack},{"decay",p.decay},{"sustain",p.sustain},{"release",p.release},{"gain",double(p.gain)},{"detuneCents",p.detune},{"osc2Mix",double(p.mix)}})extra.emplace(pair.first,pair.second);
        if(kind==1)for(auto& s:strings)s.buffer.resize(std::max(2,int(rate/frequency(0))));
        if(kind==2)voiceCount=1;if(kind==3)voiceCount=12;
        if(kind==5){LSAnalogParams t={4200,.22,.001,.08,.25,.07,8,.18f,.42f,3,2},r={2500,.35,.01,.18,.55,.12,7,.25f,.32f,2,3};
            tumbi=std::make_unique<LSInstrument>(0,sr,t,seed);reed=std::make_unique<LSInstrument>(0,sr,r,seed);tumbi->voiceCount=6;reed->voiceCount=4;scratch.resize(65536);}

    }
    float noise(){rng=rng*6364136223846793005ULL+1442695040888963407ULL;return float(double(rng>>33)/double((std::uint64_t(1)<<31)-1)*2.-1.);}
    int event(std::uint32_t type,int note,float value){
        if(kind==5){if(type==1){if(note==84)return tumbi->event(1,76,value);if(note==86)return reed->event(1,79,value);if(note>=87&&note<=108)return tumbi->event(1,note,value);}else if(type==0){if(note==84)return tumbi->event(0,76,value);if(note==86)return reed->event(0,79,value);tumbi->event(0,note,value);reed->event(0,note,value);}else if(type==3){tumbi->event(3,note,value);reed->event(3,note,value);}}
        if(type==2){if(kind==0||kind==2||kind==3)bend=double(std::clamp(value,-1.f,1.f))*double(std::max(1,note));return 0;}
        if(kind==0||kind==2||kind==3){
            if(type==1){auto end=voices.begin()+voiceCount;auto it=std::find_if(voices.begin(),end,[](const Voice& v){return v.env.stage==0;});if(it==end)it=std::min_element(voices.begin(),end,[](const Voice& a,const Voice& b){return a.note<b.note;});
                it->note=note;it->velocity=value;it->first.phase=it->second.phase=it->third.phase=it->sub.phase=0.;it->filter={};it->env.stage=1;it->captured=params;it->click=float(std::clamp(get("punch"),0.,1.))*value;
            }else for(auto& v:voices)if((type==3||v.note==note)&&v.env.stage!=0)v.env.stage=4;
        }else if(kind>=4){if(type==1)triggerIndian(note,value);else if(type==3)hitCount=0;
        }else if(type==1){auto& s=strings[note];s.length=std::max(2,int(rate/std::max(frequency(note),1.)));s.index=0;s.active=true;s.damping=.996f;for(std::uint32_t i=0;i<s.length;++i)s.buffer[i]=noise()*std::max(.2f,value);
        }else for(int n=0;n<128;++n)if(type==3||n==note)strings[n].damping=.90f;
        return 0;
    }
    void process(float* out,std::uint32_t frames){
        std::fill_n(out,frames,0.f);
        if(kind==0){const double detune=std::pow(2.,params.detune/1200.);
            for(auto& v:voices)if(v.env.stage!=0){const double hz=frequency(v.note)*std::pow(2.,bend/12.);
                for(std::uint32_t i=0;i<frames;++i){const float a=v.first.next(hz,rate,v.captured.osc1),b=v.second.next(hz*detune,rate,v.captured.osc2)*params.mix;float s=(a+b)/(1.f+params.mix);s=v.filter.process(s,v.captured,rate);s*=v.env.next(v.captured,rate)*v.velocity*params.gain;out[i]+=s;}
            }
            for(std::uint32_t i=0;i<frames;++i){const float x=out[i],x2=x*x;out[i]=x*(27.f+x2)/(27.f+9.f*x2);}
        }else if(kind==2||kind==3){
            for(int j=0;j<voiceCount;++j){auto& v=voices[j];if(v.env.stage==0)continue;double hz=frequency(v.note)*std::pow(2.,bend/12.);
                for(unsigned i=0;i<frames;++i){float s;
                    if(kind==2){float blend=float(std::clamp(get("wave"),0.,1.)),drive=float(1+std::clamp(get("drive"),0.,1.)*5),a=v.first.next(hz,rate,0),shaped=std::tanh(a*(1+blend*8)),main=a*(1-blend)+shaped*blend,sub=v.sub.next(std::max(8.,hz*.5),rate,0)*float(get("sub"));s=(main+sub)/(1+float(get("sub")));if(v.click>.0001f){s+=v.click*.28f;v.click*=.985f;}s=v.filter.process(s,v.captured,rate);s=std::tanh(s*drive);
                    }else{shapePhase+=1/std::max(1.,rate);float morph=float(.5+.5*std::sin(2*pi*.37*shapePhase)*std::cos(2*pi*.23*shapePhase));float a=v.first.next(hz,rate,2)*float(get("osc1Level")),b=v.second.next(hz*std::pow(2.,get("osc2DetuneCents")/1200),rate,3)*float(get("osc2Level")),c=v.third.next(hz*std::pow(2.,(get("osc3Interval")+get("osc3DetuneCents")/100)/12),rate,1)*float(get("osc3Level"))*(.65f+.35f*morph),sub=v.sub.next(std::max(8.,hz*.5),rate,0)*float(get("subLevel"));float denom=std::max(.1f,float(get("osc1Level"))+float(get("osc2Level"))+float(get("osc3Level"))+float(get("subLevel")));s=(a+b+c+sub)/denom;float drive=1+float(std::clamp(get("lemmingShape"),0.,1.))*(1.8f+morph);s=std::tanh(s*drive);s=v.filter.process(s,v.captured,rate);}
                    s*=v.env.next(v.captured,rate)*v.velocity*params.gain;out[i]+=s;
                }
            }if(kind==3)for(unsigned i=0;i<frames;++i)out[i]=std::tanh(out[i]);
        }else if(kind>=4){renderIndian(out,frames);if(kind==5){tumbi->process(scratch.data(),frames);for(unsigned i=0;i<frames;++i)out[i]=std::tanh(out[i]+scratch[i]*.9f);reed->process(scratch.data(),frames);for(unsigned i=0;i<frames;++i)out[i]=std::tanh(out[i]+scratch[i]*.65f);}}else for(auto& s:strings)if(s.active)for(std::uint32_t i=0;i<frames;++i)out[i]+=s.next()*.6f;
    }
    void triggerIndian(int note,float velocity){
        int stroke=note>=60&&note<72?note-60:note==45?5:note==47?6:note==72?1:note==76?0:note%12;
        const double freqs[12][3]={{880,1320,1760},{1046,1568,0},{196,392,880},{110,165,0},{740,1100,0},{82,120,0},{520,900,0},{98,147,0},{155,310,620},{64,92,128},{88,132,220},{430,860,1290}};
        const float amps[12][3]={{1,.5f,.3f},{1,.4f,0},{1,.6f,.4f},{1,.5f,0},{1,.5f,0},{1,.5f,0},{.7f,.5f,0},{1,.4f,0},{1,.55f,.22f},{1,.75f,.35f},{1,.52f,.22f},{.9f,.45f,.22f}};
        const float decay[]={.9990f,.9993f,.9994f,.9990f,.9985f,.9992f,.997f,.9995f,.9996f,.9997f,.99945f,.9982f},noiseAmt[]={.2f,.15f,.3f,.1f,.4f,.2f,.8f,.15f,.18f,.12f,.10f,.55f},noiseDecay[]={.985f,.99f,.98f,.97f,.97f,.96f,.95f,.97f,.975f,.965f,.972f,.955f};
        if(hitCount==32){std::move(hits.begin()+1,hits.end(),hits.begin());--hitCount;}auto& h=hits[hitCount++];h={};h.env=h.noiseEnv=1;h.decay=decay[stroke];h.noiseAmount=noiseAmt[stroke];h.noiseDecay=noiseDecay[stroke];
        for(int k=0;k<3;++k)if(freqs[stroke][k]>0){h.freq[k]=freqs[stroke][k];h.amp[k]=amps[stroke][k]*velocity;++h.size;}
    }
    void renderIndian(float* out,unsigned frames){
        for(int j=0;j<hitCount;++j){auto& h=hits[j];if(!h.alive())continue;for(unsigned i=0;i<frames;++i){float s=0;for(int k=0;k<h.size;++k){h.phase[k]+=h.freq[k]/rate;if(h.phase[k]>=1)h.phase[k]-=1;s+=float(std::sin(2*pi*h.phase[k]))*h.amp[k];}s*=h.env;s+=noise()*h.noiseAmount*h.noiseEnv*float(get("noiseEnabled",1));out[i]+=s*.35f;h.env*=h.decay;h.noiseEnv*=h.noiseDecay;}}
        int keep=0;for(int j=0;j<hitCount;++j)if(hits[j].alive())hits[keep++]=hits[j];hitCount=keep;
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

int ls_instrument_set(LSInstrument* p,const char* key,double value) noexcept {
 if(!p||!key||!std::isfinite(value)||std::abs(value)>24000)return -1;
 auto it=p->extra.find(key);if(it==p->extra.end())return -1;it->second=value;
 const std::string_view k=key;
 if(k=="cutoff")p->params.cutoff=value;else if(k=="resonance")p->params.resonance=value;else if(k=="attack")p->params.attack=value;else if(k=="decay")p->params.decay=value;else if(k=="sustain")p->params.sustain=value;else if(k=="release")p->params.release=value;else if(k=="gain")p->params.gain=float(value);else if(k=="detuneCents")p->params.detune=value;else if(k=="osc2Mix")p->params.mix=float(value);return 0;
}
LSInstrument* ls_instrument_create_stock(const char* name,double rate,const LSParameter* params,std::uint32_t count,std::uint64_t seed) noexcept {
 if(!name||!std::isfinite(rate)||rate<8000||rate>192000||count>64||(!params&&count))return nullptr;
 std::string_view k=name;unsigned kind=k=="LemmingBass"?2:k=="Oscillatron"?3:(k=="Indian Percussion"||k=="Bhangra Dhol")?4:k=="Bhangra Architect"?5:99;if(kind==99)return nullptr;
 for(unsigned i=0;i<count;++i)if(!params[i].id||!std::isfinite(params[i].value)||std::abs(params[i].value)>24000)return nullptr;
 try{LSAnalogParams p={kind==2?620.:3200.,kind==2?.38:.24,kind==2?.0015:.004,kind==2?.22:.14,kind==2?.78:.70,kind==2?.075:.18,8,.5f,kind==2?.82f:.48f,2,2};auto result=std::make_unique<LSInstrument>(kind,rate,p,seed);
 const std::pair<const char*,double> defaults[]={{"wave",.35},{"sub",.55},{"punch",.48},{"drive",.36},{"osc1Level",.95},{"osc2Level",.72},{"osc3Level",.48},{"subLevel",.20},{"osc2DetuneCents",7},{"osc3DetuneCents",-12},{"osc3Interval",7},{"lemmingShape",.42},{"noiseEnabled",1},{"cutoff",p.cutoff},{"resonance",p.resonance},{"attack",p.attack},{"decay",p.decay},{"sustain",p.sustain},{"release",p.release},{"gain",p.gain}};
 for(auto pair:defaults)result->extra.insert_or_assign(pair.first,pair.second);for(unsigned i=0;i<count;++i)ls_instrument_set(result.get(),params[i].id,params[i].value);return result.release();}catch(...){return nullptr;}
}
