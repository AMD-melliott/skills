// Shape of cuco's HLL tuning tables: a __device__ static constexpr array whose .data() pointer is
// returned by a __host__ __device__ function and dereferenced on the HOST.
#include <hip/hip_runtime.h>
#include <array>
#include <cstdio>
__device__ static constexpr std::array<double, 4> tab_a{1.5, 2.5, 3.5, 4.5};
__device__ static constexpr std::array<double, 4> tab_b{10.0, 20.0, 30.0, 40.0};
static constexpr std::array<double, 4> plain{1.5, 2.5, 3.5, 4.5};     // no __device__ (the agent's fix)
__host__ __device__ constexpr double const* pick(int p) { return p == 0 ? tab_a.data() : tab_b.data(); }
__host__ __device__ constexpr double const* pick_plain() { return plain.data(); }
__global__ void dev(double* out, int p) { out[0] = pick(p)[2]; out[1] = pick_plain()[2]; }
int main(int argc, char**) {
  int p = argc - 1;                                   // runtime 0
  double const* h = pick(p);
  printf("host via __device__ table: %g %g %g %g (expect 1.5 2.5 3.5 4.5)\n", h[0], h[1], h[2], h[3]);
  printf("host via plain constexpr:  %g\n", pick_plain()[2]);
  double* d; double o[2]; (void)hipMalloc(&d, 16); dev<<<1, 1>>>(d, p); (void)hipMemcpy(o, d, 16, hipMemcpyDeviceToHost);
  printf("device: __device__ table %g, plain %g (expect 3.5 3.5)\n", o[0], o[1]);
}
