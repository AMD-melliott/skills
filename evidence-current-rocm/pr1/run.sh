#!/usr/bin/env bash
# PR 1 standalone reproducers on current ROCm. One image at a time, GPU 7 only (rocm-run).
# Usage: run.sh <image-tag...>   e.g. 7.14.1-full 10.1.0-full 10.2.0-full
R=/data/melliott/moat-testing/repros; RR=/data/melliott/moat-testing/tools/rocm-run
for V in "$@"; do
 LOG=/data/melliott/moat-testing/evidence/pr1/$V.log
 # 7.14.x/10.0 images do not put the HIP runtime on the loader path; point at it (image quirk, logged).
 ( cd $R && ROCM_RUN_ARGS="-v /data/melliott/moat-testing/evidence:/ev" $RR --image rocm/dev-ubuntu-24.04:$V bash -lc '
  L=$(dirname $(ls /opt/rocm*/lib/libamdhip64.so.* /opt/rocm/core-*/lib/libamdhip64.so.* 2>/dev/null | head -1)); export LD_LIBRARY_PATH=$L:${LD_LIBRARY_PATH:-}
  echo "### image '$V' hip=$(hipconfig --version) hiplib=$L"; date -Is
  H="hipcc -w --offload-arch=gfx942 -O2"
  echo "### device properties (grid-overshoot arithmetic)"
  cat > /tmp/p.hip <<X
#include <hip/hip_runtime.h>
#include <cstdio>
int main(){hipDeviceProp_t p;hipGetDeviceProperties(&p,0);printf("%s %s multiProcessorCount=%d maxThreadsPerMultiProcessor=%d -> blocks of 512 at full occupancy=%d\n",p.name,p.gcnArchName,p.multiProcessorCount,p.maxThreadsPerMultiProcessor,p.multiProcessorCount*p.maxThreadsPerMultiProcessor/512);}
X
  $H -o /tmp/p /tmp/p.hip && /tmp/p
  echo "### wave64-partial";        $H -o /tmp/w wave64-partial/partial.hip && /tmp/w
  echo "### lds-optin";             $H -o /tmp/l lds-optin/lds.hip && /tmp/l
  echo "### image-support";         $H -o /tmp/i image-support/img.hip && /tmp/i
  echo "### device-constexpr-host (dc)";  $H -o /tmp/d device-constexpr-host/dc.hip && /tmp/d
  echo "### device-constexpr-host (dc2)"; $H -std=c++17 -o /tmp/d2 device-constexpr-host/dc2.hip && /tmp/d2
  echo "### host-minmax: default build";  $H -o /tmp/t host-minmax/t.hip && /tmp/t
  echo "### host-minmax: macro default";  echo "__HIP_DEFINE_EXTENDED_HOST_MIN_MAX__ default: $(grep -rh -A1 "ifndef __HIP_DEFINE_EXTENDED_HOST_MIN_MAX__" $(dirname $(find / -name __clang_hip_math.h 2>/dev/null | head -1)) | tail -1)"
  echo "### host-minmax: with -D__HIP_DEFINE_EXTENDED_HOST_MIN_MAX__=1"; $H -D__HIP_DEFINE_EXTENDED_HOST_MIN_MAX__=1 -o /tmp/t1 host-minmax/t.hip && /tmp/t1
  echo "### host-minmax: static_assert guard (expect build failure by default)"; $H -std=c++17 -o /tmp/g host-minmax/g.hip 2>&1 | grep -m1 -E "static assertion|error" ; echo "guard build rc=${PIPESTATUS[0]}"
  echo "### host-minmax: guard with the define (expect build ok)"; $H -std=c++17 -D__HIP_DEFINE_EXTENDED_HOST_MIN_MAX__=1 -o /tmp/g1 host-minmax/g.hip; echo "rc=$?"
  echo "### hiprtc-version"; $H -o /tmp/v hiprtc-version/v.hip -lhiprtc && /tmp/v
  echo "### libhipcxx CAS, libhipcxx amd-develop head (unpatched)"; hipcc -w -std=c++20 --offload-arch=gfx942 -O2 -I /ev/libhipcxx-head/include -o /tmp/c libhipcxx-cas/cas.hip && /tmp/c
  echo "### libhipcxx CAS, cuco port patch applied"; hipcc -w -std=c++20 --offload-arch=gfx942 -O2 -I libhipcxx-cas/patched -o /tmp/cp libhipcxx-cas/cas.hip 2>&1 | tail -2 && /tmp/cp
  B=$(find / -type d -name hipccl -path "*include*" 2>/dev/null | head -1); echo "### libhipcxx CAS, bundled hipccl: ${B:-none}"
  [ -n "$B" ] && { hipcc -w -std=c++20 --offload-arch=gfx942 -O2 -I $B -o /tmp/cb libhipcxx-cas/cas.hip 2>&1 | tail -3 && /tmp/cb; }
  echo "### libhipcxx atomic_ref under-aligned 8-byte, head (expect link error)"; hipcc -w -std=c++20 --offload-arch=gfx942 -O2 -I /ev/libhipcxx-head/include -o /tmp/a libhipcxx-align/align.hip 2>&1 | grep -m2 -iE "error" ; [ -x /tmp/a ] && /tmp/a
  [ -n "$B" ] && { echo "### atomic_ref under-aligned, bundled hipccl"; hipcc -w -std=c++20 --offload-arch=gfx942 -O2 -I $B -o /tmp/ab libhipcxx-align/align.hip 2>&1 | grep -m2 -iE "error"; [ -x /tmp/ab ] && /tmp/ab; }
  echo "### atomic_ref under-aligned, cuco port patch (expect {1,2})"; hipcc -w -std=c++20 --offload-arch=gfx942 -O2 -I libhipcxx-align/patched -o /tmp/ap libhipcxx-align/align.hip 2>&1 | grep -m2 -iE "error"; [ -x /tmp/ap ] && /tmp/ap
  date -Is' ) > $LOG 2>&1
 echo "$V done rc=$?"
done
