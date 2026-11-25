#!/usr/bin/env bash
# PR 3: llm.c port whose cooperative_groups shim gates plus/less/greater on __has_include (round-1 run 3), on current ROCm.
EV=/data/melliott/moat-testing/evidence/pr3-llmc; RR=/data/melliott/moat-testing/tools/rocm-run
for V in "$@"; do ( cd $EV && ROCM_RUN_ARGS="-v $EV:/ev0" $RR --image rocm/dev-ubuntu-24.04:$V bash -lc '
 export LD_LIBRARY_PATH=$(ls -d /opt/rocm/core-*/lib /opt/rocm/lib 2>/dev/null | tr "\n" :)${LD_LIBRARY_PATH:-}
 echo "### image '$V' hip=$(hipconfig --version)"; date -Is; rm -rf /tmp/w && cp -r /ev0/src /tmp/w && cd /tmp/w
 grep -n "__has_include" llmc/hip/cooperative_groups/reduce.h | head -2
 make USE_HIP=1 HIP_ARCH=gfx942 test_gpt2cu test_gpt2fp32cu > b.log 2>&1; echo "build rc=$?"; grep -m3 " error" b.log
 o=$(./test_gpt2cu 2>&1); echo "test_gpt2cu: $(echo "$o" | grep -iE "overall okay" | tail -1)"
 o=$(./test_gpt2fp32cu 2>&1); echo "test_gpt2fp32cu: $(echo "$o" | grep -iE "overall okay" | tail -1)"
 hipcc -std=c++17 -O3 --offload-arch=gfx942 -Illmc/hip -x hip -w ldsprobe/ln_probe.cu -o lnp -lhipblas -lhipblaslt 2>&1 | tail -2
 for C in 768 1920; do echo "C=$C: $(./lnp $C 2>&1 | tail -2 | tr "\n" " ")"; done; date -Is' ) > $EV/$V.log 2>&1; echo "$V done"; done
