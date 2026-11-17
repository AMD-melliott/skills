// What does gfx942 do with a dynamic shared-memory (LDS) request above 64 KiB?
#include <hip/hip_runtime.h>
#include <cstdio>
__global__ void k(float* out, int n) {
  extern __shared__ float s[];
  for (int i = threadIdx.x; i < n; i += blockDim.x) s[i] = i;
  __syncthreads();
  if (threadIdx.x == 0) out[blockIdx.x] = s[n - 1];
}
int main() {
  hipDeviceProp_t p; hipGetDeviceProperties(&p, 0);
  int optin = -1; hipDeviceGetAttribute(&optin, hipDeviceAttributeSharedMemPerBlockOptin, 0);
  printf("%s sharedMemPerBlock=%zu maxSharedMemoryPerMultiProcessor=%zu SharedMemPerBlockOptin=%d\n",
         p.gcnArchName, p.sharedMemPerBlock, p.maxSharedMemoryPerMultiProcessor, optin);
  float* d; hipMalloc(&d, 4);
  for (size_t kb : {48, 64, 65, 80, 96, 160, 228}) {
    size_t bytes = kb * 1024; int n = bytes / 4;
    hipGetLastError();
    hipError_t a = hipFuncSetAttribute((const void*)k, hipFuncAttributeMaxDynamicSharedMemorySize, (int)bytes);
    hipError_t aLast = hipGetLastError();
    hipLaunchKernelGGL(k, dim3(1), dim3(256), bytes, 0, d, n);
    hipError_t l = hipGetLastError();
    hipError_t s = hipDeviceSynchronize();
    float h = -1; hipMemcpy(&h, d, 4, hipMemcpyDeviceToHost); hipMemset(d, 0, 4);
    printf("%4zu KiB: setAttr=%s (lastErr=%s)  launch=%s  sync=%s  result=%s\n", kb, hipGetErrorName(a),
           hipGetErrorName(aLast), hipGetErrorName(l), hipGetErrorName(s), (h == n - 1) ? "correct" : "WRONG/none");
  }
}
