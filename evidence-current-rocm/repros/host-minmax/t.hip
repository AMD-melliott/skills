#include <hip/hip_runtime.h>
#include <cstdio>
__host__ __device__ float clampf(float x){ return min(max(x, 0.25f), 3.75f); }
int main(){
  printf("min(0.25f,3.7f)=%g max(0.5,0.75)=%g clampf(2.5f)=%g\n", (double)min(0.25f,3.7f), (double)max(0.5,0.75), (double)clampf(2.5f));
  unsigned u = 3000000000u; printf("max(3000000000u,1u)=%u\n", (unsigned)max(u,1u));
}
