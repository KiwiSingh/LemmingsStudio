#include "Host.h"
#include <cstdio>
int main(int argc,char** argv){if(argc<2)return 2;char error[2048]{};auto* h=lp_open(argv[1],argc>2?0:1,48000,512,error,sizeof(error));if(!h){std::fprintf(stderr,"%s\n",error);return 1;}std::printf("Opened, parameters=%d latency=%d\n",lp_param_count(h),lp_latency(h));float l[512]{},r[512]{};for(int i=0;i<16;i++){l[i]=r[i]=.1f;}int status=lp_process(h,l,r,512,0);std::printf("Process status=%d\n",status);lp_close(h);return status;}
