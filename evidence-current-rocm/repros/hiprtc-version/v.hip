#include <hip/hip_runtime.h>
#include <hip/hiprtc.h>
#include <cstdio>
int main() { int ma = -1, mi = -1, rt = -1, dv = -1;
  (void)hiprtcVersion(&ma, &mi); (void)hipRuntimeGetVersion(&rt); (void)hipDriverGetVersion(&dv);
  printf("hiprtcVersion=%d.%d hipRuntimeGetVersion=%d hipDriverGetVersion=%d HIP_VERSION=%d\n", ma, mi, rt, dv, HIP_VERSION); }
