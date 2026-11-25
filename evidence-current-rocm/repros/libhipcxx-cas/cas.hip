// Each thread owns ONE byte (or short) and flips it 0->1->0 with compare_exchange_strong.
// No other thread writes that byte, so a strong CAS must never fail. Neighbouring bytes in the
// same 32-bit word are flipped concurrently by other threads.
#include <cuda/atomic>
#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstdint>
constexpr int ITERS = 1000;
template <class T, int MODE>   // 0 = cuda::atomic_ref strong, 1 = raw __hip strong, 2 = raw __hip weak
__global__ void flip(T* a, unsigned long long* fails) {
  T* p = a + blockIdx.x * blockDim.x + threadIdx.x;
  unsigned long long f = 0;
  for (int i = 0; i < ITERS; i++) for (int from = 0; from < 2; from++) {
    T exp = T(from), des = T(1 - from); bool ok;
    if constexpr (MODE == 0) ok = cuda::atomic_ref<T, cuda::thread_scope_device>(*p).compare_exchange_strong(exp, des);
    else if constexpr (MODE == 1) ok = __hip_atomic_compare_exchange_strong(p, &exp, des, __ATOMIC_RELAXED, __ATOMIC_RELAXED, __HIP_MEMORY_SCOPE_AGENT);
    else ok = __hip_atomic_compare_exchange_weak(p, &exp, des, __ATOMIC_RELAXED, __ATOMIC_RELAXED, __HIP_MEMORY_SCOPE_AGENT);
    if (!ok) { f++; *p = des; }   // spurious failure: value was still `from`; force progress
  }
  atomicAdd(fails, f);
}
template <class T, int MODE> void run(const char* name) {
  const int B = 1024, TPB = 256, N = B * TPB; T* a; unsigned long long* f; unsigned long long h;
  (void)hipMalloc(&a, N * sizeof(T)); (void)hipMemset(a, 0, N * sizeof(T)); (void)hipMalloc(&f, 8); (void)hipMemset(f, 0, 8);
  flip<T, MODE><<<B, TPB>>>(a, f); (void)hipMemcpy(&h, f, 8, hipMemcpyDeviceToHost);
  printf("%-34s sizeof=%zu: %llu spurious failures of %llu CAS\n", name, sizeof(T), h, 2ull * ITERS * N);
  (void)hipFree(a); (void)hipFree(f);
}
int main() {
  run<uint8_t, 0>("cuda::atomic_ref strong (libhipcxx)"); run<uint8_t, 1>("__hip_atomic_cas_strong");  run<uint8_t, 2>("__hip_atomic_cas_weak");
  run<uint16_t, 0>("cuda::atomic_ref strong (libhipcxx)"); run<uint16_t, 1>("__hip_atomic_cas_strong"); run<uint16_t, 2>("__hip_atomic_cas_weak");
  run<uint32_t, 0>("cuda::atomic_ref strong (libhipcxx)"); run<uint32_t, 1>("__hip_atomic_cas_strong");
}
