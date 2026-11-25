#include <hip/hip_runtime.h>
#include <type_traits>
// Host-pass guard: fails the build if host min/max(float,float) still lands on (int,int).
#if !defined(__HIP_DEVICE_COMPILE__)
static_assert(std::is_same<decltype(min(1.0f, 2.0f)), float>::value,
              "host min(float,float) truncates to int: fix call sites or use ROCm >= 7.2 with __HIP_DEFINE_EXTENDED_HOST_MIN_MAX__=1");
#endif
int main(){ return (int)min(0.5f, 1.5f); }
