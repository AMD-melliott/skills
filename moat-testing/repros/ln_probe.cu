// Call llm.c's layernorm_forward at a channel count whose shared-memory request exceeds 64 KiB.
#define ENABLE_FP32
#include <cstdio>
#include <cstdlib>
#include "../llmc/cuda_common.h"
#include "../llmc/cuda_utils.cuh"
#include "../llmc/layernorm.cuh"
cudaDeviceProp deviceProp;
int main(int argc, char** argv) {
  int C = atoi(argv[1]), N = 64;
  cudaGetDeviceProperties(&deviceProp, 0);
  size_t smem = (2 + 256 / WARP_SIZE) * C * sizeof(floatX);
  printf("C=%d floatX=%zuB smem request=%zu bytes (%s 64 KiB)\n", C, sizeof(floatX), smem, smem > 65536 ? ">" : "<=");
  float *inp, *out, *mean, *rstd, *w, *b;
  cudaMalloc(&inp, N*C*4); cudaMalloc(&out, N*C*4); cudaMalloc(&mean, N*4); cudaMalloc(&rstd, N*4);
  cudaMalloc(&w, C*4); cudaMalloc(&b, C*4);
  cudaMemset(inp, 0, N*C*4); cudaMemset(w, 0, C*4); cudaMemset(b, 0, C*4);
  layernorm_forward(out, mean, rstd, inp, w, b, 1, N, C, 0);
  cudaCheck(cudaDeviceSynchronize());
  printf("layernorm_forward returned normally\n");
}
