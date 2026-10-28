// Original AudioEngine.renderMetronome click voice and boundary-pulling rule.
#include "drums.h"
#include <cmath>
#include <algorithm>
#include <numbers>
LS_API int ls_metronome(const double* beats,std::uint32_t n,double end,double rate,double tempo,std::uint32_t perBar,float volume,float* out) noexcept {
 if(!beats||!out||n>65536||!perBar||perBar>64||!std::isfinite(rate)||rate<8000||rate>192000||!std::isfinite(tempo)||tempo<20||tempo>400||!std::isfinite(end)||!std::isfinite(volume)||volume<0||volume>1)return -1;
 for(unsigned i=0;i<n;++i)if(!std::isfinite(beats[i])||beats[i]<0)return -1;
 if(!n)return 0;double boundary=std::ceil(beats[0]-1e-9);bool pull=boundary>=beats[0]&&boundary<end;double secPerBeat=60/tempo,duration=std::min(.070,secPerBeat*.45);
 for(unsigned i=0;i<n;++i){out[i]=0;double beat=i==0&&pull?boundary:beats[i],whole=std::floor(beat),seconds=(beat-whole)*secPerBeat;if(pull&&i>0&&whole==boundary&&seconds<duration)continue;if(seconds<0||seconds>=duration)continue;bool down=int(whole)%perBar==0;double freq=down?1760:1180,decay=std::exp(-seconds*(down?42:54)),tone=std::sin(2*std::numbers::pi*freq*seconds),impulse=seconds<.004?1-seconds/.004:0,click=(tone*.82+impulse*.55)*decay;out[i]=float(click)*volume*(down?1.f:.72f);}
 return 0;
}
