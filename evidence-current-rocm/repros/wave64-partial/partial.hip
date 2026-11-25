// (1) 32-thread block on wave64: warpSize/2 shuffle loop reads lanes 32..63 that have no thread.
// (2) 16-thread block running a fixed 32-wide shared-memory tree reads sdata[16..31], never written.
#include <hip/hip_runtime.h>
#include <cstdio>
__global__ void shfl_sum(float* out) {               // each thread contributes 1
  float v = 1.0f;
  for (int off = warpSize / 2; off > 0; off /= 2) v += __shfl_down(v, off);
  if (threadIdx.x == 0) out[blockIdx.x] = v;         // expect blockDim.x
}
__global__ void dirty_lds() {                        // leave junk in LDS
  __shared__ float s[1024]; for (int i = threadIdx.x; i < 1024; i += blockDim.x) s[i] = 1000.0f;
  __syncthreads(); if (s[threadIdx.x] < 0) s[0] = 0;
}
__global__ void tree32(float* out) {                 // upstream-style 32-wide tree, 1 per thread
  __shared__ float s[1024]; unsigned t = threadIdx.x;
  s[t] = 1.0f; __syncthreads();
  for (int i = 16; i > 0; i >>= 1) { if ((t & 31) < i) s[t] += s[t + i]; __syncthreads(); }
  if (t == 0) out[blockIdx.x] = s[0];                // expect blockDim.x
}
int main() {
  const int G = 4096; float *d, h[G]; (void)hipMalloc(&d, G * sizeof(float));
  int ws; (void)hipDeviceGetAttribute(&ws, hipDeviceAttributeWarpSize, 0);
  for (int bs : {64, 32}) {
    shfl_sum<<<G, bs>>>(d); (void)hipMemcpy(h, d, sizeof h, hipMemcpyDeviceToHost);
    int bad = 0; for (int i = 0; i < G; i++) bad += h[i] != bs;
    printf("warpSize=%d shfl_sum block=%d: %d/%d blocks wrong (e.g. %g)\n", ws, bs, bad, G, h[0]);
  }
  for (int bs : {32, 16}) {
    dirty_lds<<<G, 256>>>(); tree32<<<G, bs>>>(d); (void)hipMemcpy(h, d, sizeof h, hipMemcpyDeviceToHost);
    int bad = 0; for (int i = 0; i < G; i++) bad += h[i] != bs;
    printf("tree32 block=%d after dirty LDS: %d/%d blocks wrong (e.g. %g)\n", bs, bad, G, h[0]);
  }
}
