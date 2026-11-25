// Shape of cuco's HLL tuning tables: a __device__ static constexpr array whose .data() pointer is
// returned by a __host__ __device__ function and dereferenced on the HOST.
#include <cuda_runtime.h>
#include <array>
#include <cstdio>
__device__ static constexpr std::array<double, 4> tab_a{1.5, 2.5, 3.5, 4.5};
__device__ static constexpr std::array<double, 4> tab_b{10.0, 20.0, 30.0, 40.0};
__host__ __device__ constexpr double const* pick(int p) { return p == 0 ? tab_a.data() : tab_b.data(); }
__global__ void dev(double* out, int p) { out[0] = pick(p)[2]; }
int main(int argc, char**) {
  int p = argc - 1;                                   // runtime 0
  double const* h = pick(p);
  printf("host via __device__ table: %g %g %g %g (expect 1.5 2.5 3.5 4.5)\n", h[0], h[1], h[2], h[3]);
  double* d; double o[2]; (void)cudaMalloc(&d, 16); dev<<<1, 1>>>(d, p); (void)cudaMemcpy(o, d, 16, cudaMemcpyDeviceToHost);
  printf("device: __device__ table %g, plain %g (expect 3.5 3.5)\n", o[0], o[1]);
}
