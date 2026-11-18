#include <hip/hip_runtime.h>
#include <cstdio>
int main(){ hipDeviceProp_t p; if(hipGetDeviceProperties(&p,0)!=hipSuccess) return 1;
 int img=-1,tex1=-1; (void)hipDeviceGetAttribute(&img,hipDeviceAttributeImageSupport,0);
 (void)hipDeviceGetAttribute(&tex1,hipDeviceAttributeMaxTexture1DLinear,0);
 printf("%s %s imageSupport=%d maxTex1DLinear=%d\n",p.name,p.gcnArchName,img,tex1);
 hipChannelFormatDesc d=hipCreateChannelDesc<float>(); hipArray_t a=nullptr;
 printf("hipMallocArray: %s\n",hipGetErrorName(hipMallocArray(&a,&d,64,64)));
 float* buf; (void)hipMalloc(&buf,4096); hipResourceDesc r{}; r.resType=hipResourceTypeLinear; r.res.linear.devPtr=buf; r.res.linear.desc=d; r.res.linear.sizeInBytes=4096;
 hipTextureDesc t{}; hipTextureObject_t o=0; printf("hipCreateTextureObject(linear): %s\n",hipGetErrorName(hipCreateTextureObject(&o,&r,&t,nullptr)));
 return 0;}
