#include <hip/hip_runtime.h>
#include <cstdio>
int main(){int n=0;hipGetDeviceCount(&n);for(int i=0;i<n;i++){char b[64];hipDeviceGetPCIBusId(b,64,i);hipDeviceProp_t p;hipGetDeviceProperties(&p,i);printf("hip %d %s %s warp=%d lds=%zu\n",i,b,p.gcnArchName,p.warpSize,p.sharedMemPerBlock);}}
