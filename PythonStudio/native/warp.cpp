// Original WarpEngine.swift OLA / phase-vocoder / phase-locked vocoder.
#include "drums.h"
#include <array>
#include <vector>
#include <cmath>
#include <algorithm>
#include <numbers>
namespace {
constexpr int N=2048,hopA=512,bins=1025;constexpr double pi=std::numbers::pi;
void fft(std::array<double,N>& re,std::array<double,N>& im,bool inverse){
 int j=0;for(int i=0;i<N-1;++i){if(i<j){std::swap(re[i],re[j]);std::swap(im[i],im[j]);}int m=N>>1;while(m>=1&&j>=m){j-=m;m>>=1;}j+=m;}
 for(int len=2;len<=N;len<<=1){double angle=(inverse?2.:-2.)*pi/len,wlenRe=std::cos(angle),wlenIm=std::sin(angle);for(int i=0;i<N;i+=len){double wRe=1,wIm=0;for(int k=0;k<len/2;++k){double ur=re[i+k],ui=im[i+k],vr=re[i+k+len/2]*wRe-im[i+k+len/2]*wIm,vi=re[i+k+len/2]*wIm+im[i+k+len/2]*wRe;re[i+k]=ur+vr;im[i+k]=ui+vi;re[i+k+len/2]=ur-vr;im[i+k+len/2]=ui-vi;double nw=wRe*wlenRe-wIm*wlenIm;wIm=wRe*wlenIm+wIm*wlenRe;wRe=nw;}}}
}
}
LS_API int ls_warp(const float* input,std::uint32_t count,double ratio,std::uint32_t mode,float* output,std::uint32_t capacity) noexcept {
 if(!input||!output||count>192000*600||!std::isfinite(ratio)||ratio<.03125||ratio>32||mode>2)return -1;
 const auto length=count<=4096?count:std::uint32_t(double(count)*ratio)+N;if(capacity!=length||length>192000*600)return -1;
 for(unsigned i=0;i<count;++i)if(!std::isfinite(input[i]))return -1;
 if(count<=4096){std::copy_n(input,count,output);return 0;}
 try{std::fill_n(output,length,0.f);std::vector<float> norm(length,0);std::array<float,N> win{};for(int i=0;i<N;++i)win[i]=.5f-.5f*float(std::cos(2*pi*i/(N-1)));int hopS=std::max(1,int(hopA*ratio));
  if(mode==0){for(unsigned a=0,s=0;a+N<count;a+=hopA,s+=hopS)for(int i=0;i<N;++i){output[s+i]+=input[a+i]*win[i];norm[s+i]+=win[i];}}
  else{std::array<double,N> re{},im{};std::array<double,bins> last{},sum{},mag{},freq{};double expect=2*pi*hopA/N;
   for(unsigned a=0,s=0;a+N<=count;a+=hopA,s+=hopS){for(int i=0;i<N;++i){re[i]=double(input[a+i])*double(win[i]);im[i]=0;}fft(re,im,false);
    for(int k=0;k<bins;++k){double m=std::sqrt(re[k]*re[k]+im[k]*im[k]),phase=std::atan2(im[k],re[k]),delta=phase-last[k];last[k]=phase;delta-=k*expect;while(delta>pi)delta-=2*pi;while(delta<-pi)delta+=2*pi;mag[k]=m;freq[k]=k*expect+delta;}
    if(mode==2){int k=1;while(k<bins-1){if(mag[k]>mag[k-1]&&mag[k]>=mag[k+1]){int lo=k-1;while(lo>0&&mag[lo]>=mag[lo-1])--lo;int hi=k+1;while(hi<bins-1&&mag[hi]>=mag[hi+1])++hi;for(int j=lo;j<=std::min(hi,bins-1);++j)freq[j]=freq[k];k=hi+1;}else ++k;}}
    for(int k=0;k<bins;++k){sum[k]+=freq[k]*double(hopS)/hopA;re[k]=mag[k]*std::cos(sum[k]);im[k]=mag[k]*std::sin(sum[k]);}for(int k=1;k<N/2;++k){re[N-k]=re[k];im[N-k]=-im[k];}fft(re,im,true);
    for(int i=0;i<N;++i){double w=win[i];output[s+i]+=float(re[i]/N*w);norm[s+i]+=float(w*w);}
   }
  }
  for(unsigned i=0;i<length;++i)if(norm[i]>1e-6f)output[i]/=norm[i];return 0;
 }catch(...){return -1;}
}
