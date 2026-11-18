// atomic_ref on an 8-byte struct whose alignof is 4 (callers align the object to 8, as atomic_ref requires).
#include <cuda/atomic>
#include <hip/hip_runtime.h>
#include <cstdio>
struct pair_t { int a, b; };
__global__ void k(pair_t* p) {
  cuda::atomic_ref<pair_t, cuda::thread_scope_device> r(*p);
  pair_t exp{0, 0}, des{1, 2};
  (void)r.compare_exchange_strong(exp, des);
}
int main() { pair_t* p; (void)hipMalloc(&p, 8); (void)hipMemset(p, 0, 8); k<<<1, 1>>>(p);
  pair_t h; (void)hipMemcpy(&h, p, 8, hipMemcpyDeviceToHost); printf("result {%d,%d} (expect {1,2})\n", h.a, h.b); }
