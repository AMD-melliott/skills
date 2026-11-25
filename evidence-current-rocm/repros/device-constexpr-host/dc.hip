// A __device__ constexpr table read from HOST code. nvcc treats it as a constant usable on the host;
// check what HIP/clang does.
#include <hip/hip_runtime.h>
#include <cstdio>
__device__ constexpr float table[4] = {1.5f, 2.5f, 3.5f, 4.5f};
__device__ constexpr int scalar = 42;
float host_sum() { float s = 0; for (int i = 0; i < 4; i++) s += table[i]; return s; }   // runtime index
int main() { printf("host_sum=%g (expect 12) table[2]=%g scalar=%d\n", host_sum(), table[2], scalar); }
