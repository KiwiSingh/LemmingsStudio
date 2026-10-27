// Independent portable translation of the project's original Swift effects.
#include "effects.h"
#include <array>
#include <bit>

#include <vector>
#include <map>
#include <string>
#include <string_view>
#include <cmath>
#include <numbers>
#include <algorithm>
namespace {
constexpr double pi=std::numbers::pi;
float db(double v){return float(std::pow(10.,v/20.));}
float clip(float v,float lo,float hi){return std::clamp(v,lo,hi);}
struct Biquad {
 double b0=1,b1=0,b2=0,a1=0,a2=0,z1=0,z2=0;
 void update(int kind,double freq,double q,double gain,double sr){
  double A=std::pow(10.,gain/40.),w=2*pi*std::clamp(freq,20.,sr*.49)/sr,c=std::cos(w),s=std::sin(w),alpha=s/(2*std::max(q,.05));
  double B0=1,B1=0,B2=0,A0=1,A1=0,A2=0;
  switch(kind){
  case 0:B0=1+alpha*A;B1=-2*c;B2=1-alpha*A;A0=1+alpha/A;A1=-2*c;A2=1-alpha/A;break;
  case 1:{double t=2*std::sqrt(A)*alpha;B0=A*((A+1)-(A-1)*c+t);B1=2*A*((A-1)-(A+1)*c);B2=A*((A+1)-(A-1)*c-t);A0=(A+1)+(A-1)*c+t;A1=-2*((A-1)+(A+1)*c);A2=(A+1)+(A-1)*c-t;break;}
  case 2:{double t=2*std::sqrt(A)*alpha;B0=A*((A+1)+(A-1)*c+t);B1=-2*A*((A-1)+(A+1)*c);B2=A*((A+1)+(A-1)*c-t);A0=(A+1)-(A-1)*c+t;A1=2*((A-1)-(A+1)*c);A2=(A+1)-(A-1)*c-t;break;}
  case 3:B0=(1-c)/2;B1=1-c;B2=(1-c)/2;A0=1+alpha;A1=-2*c;A2=1-alpha;break;
  case 4:B0=(1+c)/2;B1=-(1+c);B2=(1+c)/2;A0=1+alpha;A1=-2*c;A2=1-alpha;break;
  }
  b0=B0/A0;b1=B1/A0;b2=B2/A0;a1=A1/A0;a2=A2/A0;
 }
 double process(double x){double y=b0*x+z1;z1=b1*x-a1*y+z2;z2=b2*x-a2*y;return y;}
};
struct Line {std::vector<float> data;int index=0;float store=0;};
enum Family{utility,saturation,align,delay,reverb,autopan,chorus,repeat,gate,limiter,eq3,eq8,cabinet,filter,compressor,glue,redux,resonator,drumbuss,erosion,vinyl,channel,architect,character,shaper,vocoder,analyzer,tune};
constexpr std::array<std::string_view,28> names={"utility","saturation","align","delay","reverb","autopan","chorus","repeat","gate","limiter","eq3","eq8","cabinet","filter","compressor","glue","redux","resonator","drumbuss","erosion","vinyl","channel","architect","character","shaper","vocoder","analyzer","tune"};
#include "effects_schema.h"
}
struct LSEffect {
 Family kind;double sr,tempo;std::map<std::string,double,std::less<>> values;
 std::array<Biquad,8> l{},r{};
 std::array<bool,8> enabled={false,true,true,true,true,true,true,false};
 std::array<Line,12> linesL,linesR;
 std::vector<float> bufL,bufR;
 std::array<float,2048> window{};std::array<float,8192> pitchline{};
 int lookCount=1,index=0,counter=0,play=0,stutter=0,wpos=0,lwrite=0;double phase=0,oscPhase=0,subPhase=0,envDB=-60,readPos=0,ratio=1,oneL=0,twoL=0,oneR=0,twoR=0;
 float lpL=0,lpR=0,envL=0,envR=0,gain=1,holdL=0,holdR=0,meterPeak=0,meterRMS=0;double crossings=0,lastGR=0;std::uint64_t rng=0;
 double p(const char* id,double fallback=0)const {auto it=values.find(id);return it==values.end()?fallback:it->second;}
 float noise(bool vinylNoise=false){rng=rng*(vinylNoise?6364136223846793005ULL:2862933555777941757ULL)+(vinylNoise?1442695040888963407ULL:3037000493ULL);auto signedBits=std::bit_cast<std::int64_t>(rng);return float(signedBits>>40)/float(1<<23);}
 LSEffect(Family k,double rate,double bpm,const LSParameter* params,unsigned n):kind(k),sr(rate),tempo(bpm){
  for(unsigned i=0;i<n;++i)values.emplace(params[i].id,params[i].value);
  int capacity=0;
  if(k==align)capacity=std::max(1024,int(sr*.25));
  if(k==delay||k==chorus)capacity=std::max(2048,int(sr*2));
  if(k==repeat)capacity=std::max(4096,int(sr*60/tempo*8));
  if(k==limiter)capacity=8192;
  if(k==architect)capacity=std::clamp(int(sr*2),2048,262144);
  bufL.resize(capacity);bufR.resize(capacity);
  if(k==reverb){constexpr int tunes[]={1116,1188,1277,1356,1422,1491,1557,1617,556,441,341,225};for(int i=0;i<12;++i){linesL[i].data.resize(std::max(1,int(tunes[i]*sr/44100)));linesR[i].data.resize(std::max(1,int((tunes[i]+23)*sr/44100)));}}
  if(k==glue)envDB=-90;
  if(k==erosion)rng=0x726f6775656c656dULL;if(k==vinyl)rng=0x76696e796c6c656dULL;if(k==architect)rng=0x6678617263686974ULL;
  if(k==limiter)lookCount=std::clamp(int(sr*std::max(0.,p("lookahead"))*.001),1,8192);
  recompute();
 }
 // Several original effects deliberately copy left filter state to right when
 // recomputing each host block. Preserve this observable baseline behavior.
 void pair(int slot,int mode,double freq,double q,double g){l[slot].update(mode,freq,q,g,sr);r[slot]=l[slot];}
 void recompute(){
  switch(kind){
  case cabinet:pair(0,4,70+p("size")*120,.7,0);pair(1,0,650+p("character")*1700,.9,2+p("character")*5);pair(2,3,3200+p("size")*4500,.8,0);break;
  case eq3:pair(0,1,p("lowFreq"),.7,p("low"));pair(1,2,p("highFreq"),.7,p("high"));break;
  case eq8:{const int modes[]={4,1,0,0,0,0,2,3};constexpr const char* keys[8][3]={{"b0_gain","b0_freq","b0_q"},{"b1_gain","b1_freq","b1_q"},{"b2_gain","b2_freq","b2_q"},{"b3_gain","b3_freq","b3_q"},{"b4_gain","b4_freq","b4_q"},{"b5_gain","b5_freq","b5_q"},{"b6_gain","b6_freq","b6_q"},{"b7_gain","b7_freq","b7_q"}};for(int b=0;b<8;++b){double g=p(keys[b][0]);enabled[b]=enabled[b]||std::abs(g)>.01;l[b].update(modes[b],p(keys[b][1]),p(keys[b][2]),g,sr);r[b].update(modes[b],p(keys[b][1]),p(keys[b][2]),g,sr);}break;}
  case resonator:{const double ratios[]={1,1.5,2,2.5,3};for(int b=0;b<5;++b){l[b]={};pair(b,0,std::min(sr*.45,p("root")*ratios[b]),4+p("decay")*30,6+p("decay")*10);}break;}
  case drumbuss:pair(0,4,28,.65,0);pair(1,0,64,1.1,p("boom")*8);pair(2,2,7200,.8,1.5+p("crunch")*4);break;
  case erosion:pair(0,0,p("frequency"),.45+p("width")*8,9);break;
  case vinyl:pair(0,3,10500-p("age")*5500,.7,0);pair(1,4,1800,.7,0);break;
  case channel:pair(0,4,p("highpass"),.7,0);pair(1,0,720,.9,p("body"));pair(2,2,9000,.7,p("air"));break;
  case character:pair(0,4,28+120*p("intensity"),.7,0);pair(1,0,180+p("tone")*4200,.8+p("intensity")*4,-2+p("intensity")*8);pair(2,3,1800+p("tone")*15000,.75+p("intensity")*.6,0);break;
  case vocoder:pair(0,0,250+p("formant")*3200,3,9);pair(1,2,4500,.8,-3+p("formant")*8);break;
  case architect:pair(0,4,35+p("tone")*260,.72,0);pair(1,0,std::max(80.,p("root")*(1+p("tone")*8)),.7+p("sweep")*7,2+p("intensity")*8);pair(2,3,900+p("tone")*15000,.7+p("sweep")*1.4,0);break;
  default:break;
  }
 }
 float svf(float x,double fc,double resonance,bool right){double &one=right?oneR:oneL,&two=right?twoR:twoL;double g=std::tan(pi*std::clamp(fc,20.,sr*.45)/sr),k=2-1.98*std::clamp(resonance,0.,1.),a1=1/(1+g*(g+k)),a2=g*a1,a3=g*a2,v3=double(x)-two,v1=a1*one+a2*v3,v2=two+a2*one+a3*v3;one=2*v1-one;two=2*v2-two;return float(v2);}
 static float comb(Line& line,float input,float fb,float d1,float d2){float y=line.data[line.index];line.store=y*d2+line.store*d1;line.data[line.index]=input+line.store*fb;line.index=(line.index+1)%line.data.size();return y;}
 static float ap(Line& line,float x){float b=line.data[line.index],y=-x+b;line.data[line.index]=x+b*.5f;line.index=(line.index+1)%line.data.size();return y;}
 void updatePitch(){int best=0;float corr=0;for(int lag=int(sr/1000);lag<std::min(int(sr/60),1024);++lag){float c=0;for(int i=0;i<2048-lag;++i)c+=window[i]*window[i+lag];if(c>corr){corr=c;best=lag;}}if(best<=0||corr<=.01f){ratio=1;return;}double freq=sr/best,midi=69+12*std::log2(freq/440),target=std::round(midi);const int offsets[]={0,1,-1,2,-2,3,-3};for(int d:offsets){int c=int(target)+d,pc=((c-int(p("keyRoot")))%12+12)%12;if(int(p("scaleMask",0b101011010101))&(1<<pc)){target=c;break;}}ratio=440*std::pow(2.,(target-69)/12)/freq;if(!std::isfinite(ratio)||ratio<.5||ratio>2)ratio=1;}
 void process(float* a,unsigned count,const float* sc){
  if(kind==analyzer){float sum=0,peak=0,prev=0;int zc=0;for(unsigned i=0;i<count;++i){float m=(a[2*i]+a[2*i+1])*.5f;sum+=m*m;peak=std::max(peak,std::abs(m));if((m>=0)!=(prev>=0))++zc;prev=m;}meterPeak=meterPeak*.85f+peak*.15f;meterRMS=meterRMS*.85f+std::sqrt(sum/float(std::max(1u,count)))*.15f;crossings=crossings*.85+zc*.15;}
  if(kind!=eq8)recompute(); // EQ setters update coefficients without cross-channel state copying.
  const float wet=float(p("mix",1)),dry=1-wet,out=db(p("output"));const int cap=int(bufL.size());
  for(unsigned i=0;i<count;++i){float L=a[2*i],R=a[2*i+1],x=L,y=R;
   switch(kind){
   case utility:{if(p("swap")>=.5)std::swap(x,y);float mid=(x+y)*.5f,side=(x-y)*.5f*float(p("width",1));x=mid+side;y=mid-side;if(p("mono")>=.5)x=y=mid;float b=float(p("balance")),g=db(p("gain"));x=x*g*(b>0?1-b:1)*(p("invertL")>=.5?-1:1);y=y*g*(b<0?1+b:1)*(p("invertR")>=.5?-1:1);break;}
   case saturation:{float drive=db(p("drive")),t=float(p("tone"));x=std::tanh(x*drive);y=std::tanh(y*drive);lpL+=(x-lpL)*(.03f+.35f*t);lpR+=(y-lpR)*(.03f+.35f*t);x=lpL+(x-lpL)*(.25f+1.5f*t);y=lpR+(y-lpR)*(.25f+1.5f*t);x=(L*dry+x*wet)*out;y=(R*dry+y*wet)*out;break;}
   case align:{int d=std::clamp(int(p("delay")*.001*sr),0,cap-1);bufL[index]=L;bufR[index]=R;int read=(index-d+cap)%cap;x=bufL[read]*(p("polarity")>=.5?-1:1);y=bufR[read]*(p("polarity")>=.5?-1:1);index=(index+1)%cap;break;}
   case delay:{int d=std::max(1,int(p("time")/1000*sr)),read=((index-d)%cap+cap)%cap;float dl=bufL[read],dr=bufR[read],damp=float(p("damp")),pp=float(p("pingpong")),fb=float(p("feedback"));lpL=dl*(1-damp)+lpL*damp;lpR=dr*(1-damp)+lpR*damp;bufL[index]=L+(lpL*(1-pp)+lpR*pp)*fb;bufR[index]=R+(lpR*(1-pp)+lpL*pp)*fb;index=(index+1)%cap;x=L*dry+dl*wet;y=R*dry+dr*wet;break;}
   case reverb:{float oL=0,oR=0,fb=float(.28+p("size")*.7),d1=float(p("damp")),d2=1-d1;for(int b=0;b<8;++b){oL+=comb(linesL[b],L*.015f,fb,d1,d2);oR+=comb(linesR[b],R*.015f,fb,d1,d2);}for(int b=8;b<12;++b){oL=ap(linesL[b],oL);oR=ap(linesR[b],oR);}float wL=oL*float(p("width"))+oR*float(1-p("width")),wR=oR*float(p("width"))+oL*float(1-p("width"));x=L*dry+wL*wet;y=R*dry+wR*wet;break;}
   case autopan:{phase+=p("rate")/sr;if(phase>=1)phase-=1;double v=std::sin(2*pi*phase);if(p("shape")>.5)v=v>=0?1:-1;float pan=float(v*p("amount"));x*=pan>0?1-pan:1;y*=pan<0?1+pan:1;break;}
   case chorus:{phase+=p("rate")/sr;if(phase>=1)phase-=1;double dms=p("base")+p("depth")*(.5+.5*std::sin(2*pi*phase));int d=std::clamp(int(dms*.001*sr),1,cap-2),read=(index-d+cap)%cap;float dl=bufL[read],dr=bufR[read],fb=float(p("feedback"));bufL[index]=L+dl*fb;bufR[index]=R+dr*fb;index=(index+1)%cap;x=L*dry+dl*wet;y=R*dry+dr*wet;break;}
   case repeat:{double spb=sr*60/tempo;int slice=std::max(1,int(std::max(.03125,p("grid"))*spb)),period=std::max(slice,int(std::max(.03125,p("interval"))*spb)),active=int(slice*p("chance"));int phaseIn=index%period;bool go=active>0&&phaseIn<active&&index>slice;if(phaseIn==0){stutter=(index-slice+cap)%cap;play=0;}bufL[index%cap]=L;bufR[index%cap]=R;if(go){int read=(stutter+play%slice)%cap;x=L*dry+bufL[read]*wet;y=R*dry+bufR[read]*wet;++play;}else play=0;index=(index+1)%std::max(1,period*128);break;}
   case gate:{float th=db(p("threshold")),floor=db(p("floor")),atk=float(std::exp(-1/(std::max(.1,p("attack"))*.001*sr))),rel=float(std::exp(-1/(std::max(1.,p("release"))*.001*sr))),level=std::max(std::abs(L),std::abs(R)),target=level>th?1:floor,c=target>envL?atk:rel;envL=target+c*(envL-target);x*=envL;y*=envL;break;}
   case limiter:{float ceiling=db(p("ceiling")),drive=std::max(.0001f,ceiling/std::max(.0001f,db(p("threshold")))),release=float(std::exp(-1/(std::max(1.,p("release"))*.001*sr))),blend=float(p("softclip"));float dl=bufL[index],dr=bufR[index];bufL[index]=L;bufR[index]=R;index=(index+1)%lookCount;float peak=std::max(std::abs(L),std::abs(R))*drive,target=peak>ceiling?ceiling/std::max(peak,.000001f):1;gain=target<gain?target:target+release*(gain-target);x=dl*drive*gain;y=dr*drive*gain;if(blend>0){float cl=std::tanh(x/std::max(.0001f,ceiling))*ceiling,cr=std::tanh(y/std::max(.0001f,ceiling))*ceiling;x=x*(1-blend)+cl*blend;y=y*(1-blend)+cr*blend;}x=clip(x,-ceiling,ceiling)*out;y=clip(y,-ceiling,ceiling)*out;break;}
   case eq3:x=float(l[1].process(l[0].process(L)))*db(p("mid"));y=float(r[1].process(r[0].process(R)))*db(p("mid"));break;
   case eq8:{double xl=L,yr=R;for(int b=0;b<8;++b)if(enabled[b]){xl=l[b].process(xl);yr=r[b].process(yr);}x=float(xl);y=float(yr);break;}
   case cabinet:x=L*dry+float(l[2].process(l[1].process(l[0].process(L))))*wet;y=R*dry+float(r[2].process(r[1].process(r[0].process(R))))*wet;break;
   case filter:{float rect=(std::abs(L)+std::abs(R))*.5f;envL+=(rect>envL?.01f:.0005f)*(rect-envL);phase+=p("lfoRate")/sr;if(phase>=1)phase-=1;double fc=std::clamp(p("cutoff")+double(envL)*p("env")+std::sin(2*pi*phase)*p("lfoAmt"),40.,sr*.45);x=svf(L,fc,p("resonance"),false);y=svf(R,fc,p("resonance"),true);break;}
   case compressor:case glue:{double program=std::max(std::abs(double(L)),std::abs(double(R))),detect=sc?std::max(std::abs(double(sc[2*i])),std::abs(double(sc[2*i+1]))):program,blend=sc?p("sidechainMix",1):1,peak=kind==glue?std::max(1e-9,program*(1-blend)+detect*blend):std::max(1e-6,std::max(program*(1-blend),detect*blend)),level=20*std::log10(peak),atk=std::exp(-1/(p("attack")*.001*sr)),rel=std::exp(-1/(p("release")*.001*sr)),coef=level>envDB?atk:rel;envDB=level+coef*(envDB-level);double knee=kind==glue?p("knee"):6,over=envDB-p("threshold"),gr=0;if(over>knee/2)gr=over*(1/p("ratio")-1);else if(over>-knee/2){double t=over+knee/2;gr=((1/p("ratio")-1)*t*t)/(2*knee);}if(kind==glue){gr=std::max(gr,-std::max(.1,p("range")));lastGR=gr;double autoDB=p("autoMakeup")>=.5?std::clamp(-gr*.45,0.,9.):0,g=std::pow(10.,(gr+p("makeup")+autoDB)/20),drive=p("drive"),sat=1+drive*2.5;double wl=L*g,wr=R*g;if(drive>.001){wl=std::tanh(wl*sat)/std::tanh(sat);wr=std::tanh(wr*sat)/std::tanh(sat);}x=L*dry+float(wl)*wet;y=R*dry+float(wr)*wet;}else{float g=float(std::pow(10.,gr/20)*std::pow(10.,p("makeup")/20));x*=g;y*=g;}break;}
   case redux:{float steps=float(std::pow(2.,std::clamp(p("bits"),2.,24.))-1);if(counter==0){holdL=std::round(L*steps)/steps;holdR=std::round(R*steps)/steps;}counter=(counter+1)%std::max(1,int(p("downsample")));x=L*dry+holdL*wet;y=R*dry+holdR*wet;break;}
   case resonator:{double xl=0,yr=0;for(int b=0;b<5;++b){xl+=l[b].process(L);yr+=r[b].process(R);}x=L*dry+float(xl/5)*wet;y=R*dry+float(yr/5)*wet;break;}
   case drumbuss:{float d=float(1+p("drive")*6),c=float(p("crunch")),tr=float(p("transient"));float pkL=std::abs(L),pkR=std::abs(R);envL+=(pkL-envL)*(pkL>envL?.25f:.0025f);envR+=(pkR-envR)*(pkR>envR?.25f:.0025f);float snapL=clip((pkL-envL)*3,-.25f,.45f)*tr,snapR=clip((pkR-envR)*3,-.25f,.45f)*tr;x=float(l[0].process(L+(L>0?1.f:L<0?-1.f:0)*snapL));y=float(r[0].process(R+(R>0?1.f:R<0?-1.f:0)*snapR));x=float(l[1].process(x));y=float(r[1].process(y));x=x*(1-c)+std::round(x*96)/96*c;y=y*(1-c)+std::round(y*96)/96*c;x=std::tanh(x*d)/std::max(1.f,d*.52f);y=std::tanh(y*d)/std::max(1.f,d*.52f);x=clip(float(l[2].process(x))*out,-1.2f,1.2f);y=clip(float(r[2].process(y))*out,-1.2f,1.2f);break;}
   case erosion:{float n1=float(l[0].process(noise())),n2=float(r[0].process(noise())),amt=float(p("amount"));x=p("mode")>=.5?L*(1+n1*amt*2.5f):L+n1*amt;y=p("mode")>=.5?R*(1+n2*amt*2.5f):R+n2*amt;x=L*dry+std::tanh(x)*wet;y=R*dry+std::tanh(y)*wet;break;}
   case vinyl:{phase+=1/std::max(1.,sr);float wow=float(1+std::sin(2*pi*.45*phase)*p("warp")*.04+std::sin(2*pi*3.2*phase)*p("warp")*.012),dust=float(p("dust"));float crackL=(std::abs(noise(true))>.985f?noise(true)*.45f:noise(true)*.012f)*dust,crackR=(std::abs(noise(true))>.985f?noise(true)*.45f:noise(true)*.012f)*dust;x=float(l[0].process(L*wow));y=float(r[0].process(R/std::max(.9f,wow)));float d=float(1+p("drive")*5);x=std::tanh(x*d)/std::max(1.f,d*.6f)+float(l[1].process(crackL));y=std::tanh(y*d)/std::max(1.f,d*.6f)+float(r[1].process(crackR));x=L*dry+x*wet;y=R*dry+y*wet;break;}
   case channel:{x=float(l[0].process(L));y=float(r[0].process(R));x=float(l[1].process(x));y=float(r[1].process(y));x=float(l[2].process(x));y=float(r[2].process(y));float d=float(1+p("drive")*3);x=std::tanh(x*d)/std::max(1.f,d*.7f)*out;y=std::tanh(y*d)/std::max(1.f,d*.7f)*out;break;}
   case character:{phase+=(.1+p("motion")*6)/sr;if(phase>=1)phase-=1;float lfo=float(.5+.5*std::sin(2*pi*phase)),d=float(1+p("intensity")*3.5),motion=float(p("motion"));x=float(l[2].process(l[1].process(l[0].process(L))));y=float(r[2].process(r[1].process(r[0].process(R))));float mod=1-motion*.45f+motion*.9f*lfo;x=std::tanh(x*d)/std::max(1.f,d*.55f);y=std::tanh(y*d)/std::max(1.f,d*.55f);x=(L*dry+x*wet*mod)*out;y=(R*dry+y*wet*(1-motion*.25f+motion*.5f*(1-lfo)))*out;break;}
   case shaper:{float sym=float(p("symmetry"))*.35f,d=db(p("drive")),c=float(p("curve"));auto shape=[&](float v){v=(v+sym)*d;return(std::tanh(v)*(1-c)+clip(v,-1,1)*c)-sym*.5f;};x=(L*dry+shape(L)*wet)*out;y=(R*dry+shape(R)*wet)*out;break;}
   case vocoder:{float mono=(std::abs(L)+std::abs(R))*.5f;envL+=(mono-envL)*(mono>envL?.08f:.006f);phase+=p("carrier")/sr;if(phase>=1)phase-=1;float rob=float(p("robot")),saw=float(2*phase-1),pulse=phase<.5?1.f:-1.f,carrier=saw*(1-rob)+pulse*rob;x=float(l[1].process(l[0].process(carrier*envL*2.4f+L*.18f)));y=float(r[1].process(r[0].process(carrier*envL*2.4f+R*.18f)));x=L*dry+std::tanh(x*1.6f)*wet;y=R*dry+std::tanh(y*1.6f)*wet;break;}
   case tune:{float mono=(L+R)*.5f;window[wpos]=mono;wpos=(wpos+1)%2048;if(wpos==0)updatePitch();pitchline[lwrite]=mono;readPos+=1+(ratio-1)*p("amount")*(.3+.7*(p("mode")/2));if(readPos>=8192)readPos-=8192;int i0=int(readPos)%8192,i1=(i0+1)%8192;float frac=float(readPos-std::floor(readPos));x=y=pitchline[i0]*(1-frac)+pitchline[i1]*frac;lwrite=(lwrite+1)%8192;break;}
   case analyzer:break;
   case architect:{processArchitect(L,R,x,y,wet,dry,out,cap);break;}
   }
   a[2*i]=x;a[2*i+1]=y;
  }
 }
 void processArchitect(float L,float R,float& x,float& y,float wet,float dry,float out,int cap){
  double intensity=p("intensity"),sweep=p("sweep"),tone=p("tone"),stereo=p("stereo");int preset=int(std::round(p("preset")));phase+=1/(sr*std::max(.25,p("length")));if(phase>=1)phase-=std::floor(phase);double t=phase;float rise=float(std::pow(t,.55+(1-sweep)*1.2)),fall=float(std::pow(1-t,1.2)),click=float(std::exp(-t*(18+intensity*34))),shimmer=float(std::sin(2*pi*(t*(8+sweep*40)+t*t*(12+sweep*80))));double hz=std::max(35.,p("root")*std::pow(2.,(preset==3?4*(1-t):.25+4.75*t)*sweep));oscPhase+=hz/sr;subPhase+=std::max(18.,hz*.5)/sr;if(oscPhase>=1)oscPhase-=std::floor(oscPhase);if(subPhase>=1)subPhase-=std::floor(subPhase);float n=noise(),n2=noise(),st=float(stereo);auto saw=[](double ph){return float(std::tanh(2*(ph-std::floor(ph+.5))*2));};
  switch(preset){case 1:{float env=rise*float(.18+intensity),signal=std::sin(float(2*pi*oscPhase))*.62f+saw(oscPhase)*.22f+std::sin(float(2*pi*subPhase))*.16f;x=signal*env+n*env*float(.05+tone*.08);y=(signal*(1-st*.18f)+n2*st*.22f)*env;break;}
  case 2:{float body=std::sin(float(2*pi*subPhase))*click*float(1.8+intensity),thwack=(std::abs(n)>.78f?n:n*.25f)*click*float(1.2+intensity);x=body+thwack;y=body*.95f+(std::abs(n2)>.80f?n2:n2*.25f)*click*float(1.1+intensity);break;}
  case 3:{float env=fall*float(.20+intensity);x=(n*.55f+shimmer*.30f+saw(oscPhase)*.15f)*env;y=(n2*.55f-shimmer*.24f+saw(oscPhase+.015)*.15f)*env;break;}
  case 4:{float env=std::sin(float(pi*t))*float(.24+intensity);x=(n*.70f+shimmer*.20f)*env;y=(n2*.70f-shimmer*.16f)*env;break;}
  default:{float env=rise*float(.22+intensity);x=(n*.60f+shimmer*.26f+saw(oscPhase)*.14f)*env;y=(n2*.60f-shimmer*.20f+saw(oscPhase+.01)*.14f)*env;break;}}
  x=float(l[0].process(x));y=float(r[0].process(y));x=float(l[1].process(x));y=float(r[1].process(y));x=float(l[2].process(x));y=float(r[2].process(y));float drive=float(1+intensity*2.5);x=std::tanh(x*drive)/std::max(1.f,drive*.7f);y=std::tanh(y*drive)/std::max(1.f,drive*.7f);int tap=std::clamp(int(sr*(.045+stereo*.12)),1,cap-1),read=(index-tap+cap)%cap;float dl=bufL[read],dr=bufR[read],feedback=float(.18+intensity*.38);bufL[index]=x+dr*feedback*st;bufR[index]=y+dl*feedback*st;index=(index+1)%cap;x=L*dry+(x+dl*float(.28+stereo*.45))*out*wet;y=R*dry+(y+dr*float(.28+stereo*.45))*out*wet;
 }
};
LSEffect* ls_effect_create(const char* name,double rate,double tempo,const LSParameter* params,std::uint32_t n) noexcept {
 if(!name||!std::isfinite(rate)||rate<8000||rate>192000||!std::isfinite(tempo)||tempo<20||tempo>400||n>128||(!params&&n))return nullptr;
 auto it=std::find(names.begin(),names.end(),name);if(it==names.end())return nullptr;
 for(unsigned i=0;i<n;++i)if(!validParameter(Family(it-names.begin()),params[i].id,params[i].value))return nullptr;
 for(auto& range:ranges)if(range.family==Family(it-names.begin())){bool found=false;for(unsigned i=0;i<n;++i)if(std::string_view(params[i].id)==range.key)found=true;if(!found)return nullptr;}
 try{return new LSEffect(Family(it-names.begin()),rate,tempo,params,n);}catch(...){return nullptr;}
}
void ls_effect_destroy(LSEffect* p) noexcept {delete p;}
int ls_effect_set(LSEffect* p,const char* key,double value) noexcept {if(!p||!validParameter(p->kind,key,value))return -1;auto it=p->values.find(key);if(it==p->values.end())return -1;it->second=value;if(p->kind==limiter&&std::string_view(key)=="lookahead"){int count=std::clamp(int(p->sr*std::max(0.,value)*.001),1,8192);if(count!=p->lookCount){p->lookCount=count;p->index=0;std::fill(p->bufL.begin(),p->bufL.end(),0);std::fill(p->bufR.begin(),p->bufR.end(),0);}}if(p->kind==eq8)p->recompute();return 0;}
int ls_effect_process(LSEffect* p,float* audio,std::uint32_t n,const float* sc) noexcept {if(!p||!audio||n>65536)return -1;p->process(audio,n,sc);return 0;}
int ls_effect_reset(LSEffect* p) noexcept {
 if(!p)return -1;
 p->l={};p->r={};p->enabled={false,true,true,true,true,true,true,false};
 for(auto* lines:{&p->linesL,&p->linesR})for(auto& line:*lines){std::fill(line.data.begin(),line.data.end(),0);line.index=0;line.store=0;}
 std::fill(p->bufL.begin(),p->bufL.end(),0);std::fill(p->bufR.begin(),p->bufR.end(),0);p->window={};p->pitchline={};
 p->index=p->counter=p->play=p->stutter=p->wpos=p->lwrite=0;p->phase=p->oscPhase=p->subPhase=p->readPos=p->oneL=p->twoL=p->oneR=p->twoR=0;p->ratio=1;p->envDB=p->kind==glue?-90:-60;
 p->lpL=p->lpR=p->envL=p->envR=p->holdL=p->holdR=p->meterPeak=p->meterRMS=0;p->crossings=p->lastGR=0;p->gain=1;
 if(p->kind==erosion)p->rng=0x726f6775656c656dULL;if(p->kind==vinyl)p->rng=0x76696e796c6c656dULL;if(p->kind==architect)p->rng=0x6678617263686974ULL;
 p->recompute();return 0;
}
int ls_effect_tempo(LSEffect* p,double bpm) noexcept {if(!p||!std::isfinite(bpm)||bpm<20||bpm>400)return -1;if(p->kind==repeat&&p->tempo!=bpm){int capacity=std::max(4096,int(p->sr*60/bpm*8));if(capacity!=int(p->bufL.size())){try{p->bufL.assign(capacity,0);p->bufR.assign(capacity,0);p->index=p->play=p->stutter=0;}catch(...){return -1;}}}p->tempo=bpm;return 0;}

LS_API int ls_effect_get(LSEffect* p,const char* key,double* value) noexcept {if(!p||!key||!value)return -1;std::string_view name=key;if(p->kind==analyzer){if(name=="peak")*value=p->meterPeak;else if(name=="rms")*value=p->meterRMS;else if(name=="activity")*value=std::min(1.,p->crossings/std::max(1.,p->sr*.02));else if(name=="rate")*value=1;else return -1;}else if(p->kind==glue&&name=="gainReduction")*value=p->lastGR;else {auto it=p->values.find(key);if(it==p->values.end())return -1;*value=it->second;}return 0;}
