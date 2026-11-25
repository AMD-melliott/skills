#!/usr/bin/env bash
# PR 1 llm.c claims on current ROCm: fence A/B, grid bound, LDS opt-in abort. Source: round-1 blind port of
# karpathy/llm.c@f1e2ace (src/, its working-tree changes applied). GPU 7 only.
EV=/data/melliott/moat-testing/evidence/pr1-llmc; RR=/data/melliott/moat-testing/tools/rocm-run
for V in "$@"; do ( cd $EV && ROCM_RUN_ARGS="-v $EV:/ev0" $RR --image rocm/dev-ubuntu-24.04:$V bash -lc '
 export LD_LIBRARY_PATH=$(ls -d /opt/rocm/core-*/lib /opt/rocm/lib 2>/dev/null | tr "\n" :)${LD_LIBRARY_PATH:-}
 echo "### image '$V' hip=$(hipconfig --version)"; date -Is
 M="make USE_HIP=1 HIP_ARCH=gfx942"
 cd /ev0; rm -rf /tmp/w && cp -r src /tmp/w && cd /tmp/w
 echo "### port as delivered: test matrix (BF16/FP32 x 5 configs, then test_gpt2fp32cu)"
 for p in BF16 FP32; do make clean >/dev/null 2>&1; $M test_gpt2cu PRECISION=$p >b_$p.log 2>&1 || { echo "BUILD FAIL $p"; grep -m3 " error" b_$p.log; continue; }
  for a in "" "-r 0" "-r 2" "-w 0" "-b 32"; do o=$(./test_gpt2cu $a 2>&1); echo "$p [$a] $(echo "$o" | grep -iE "overall okay|^Error|abort" | tail -1) | nondet=$(echo "$o" | grep -ci "nondetermin") | NOT-OK=$(echo "$o" | grep -c "NOT OK")"; done; done
 $M test_gpt2fp32cu >b_f.log 2>&1 && echo "test_gpt2fp32cu: $(./test_gpt2fp32cu 2>&1 | grep "overall okay" | tail -1)" || { echo "BUILD FAIL test_gpt2fp32cu"; grep -m3 " error" b_f.log; }
 echo "### LDS: layernorm_forward probe via the port, FP32 (no fallback for the refused opt-in in this port)"
 hipcc -std=c++17 -O3 --offload-arch=gfx942 -Illmc/hip_compat -x hip -w ldsprobe/ln_probe.cu -o lnp -lhipblas -lhipblaslt 2>&1 | tail -3
 for C in 768 1638 1639 1920; do echo "C=$C: $(./lnp $C 2>&1 | tail -2 | tr "\n" " ")"; done
 echo "### fence A/B: layernorm.cuh reverted to upstream (no __threadfence), BF16 test x3"
 rm -rf /tmp/w && cp -r /ev0/src-nofence /tmp/w && cd /tmp/w; make clean >/dev/null 2>&1; $M test_gpt2cu >b_nf.log 2>&1 || grep -m3 " error" b_nf.log
 for i in 1 2 3; do o=$(./test_gpt2cu 2>&1); echo "run $i: $(echo "$o" | grep -iE "overall okay|^Error" | tail -1) | $(echo "$o" | grep -m1 -i "nondetermin")"; done
 echo "### grid: global_norm.cuh reverted to upstream (grid from multiProcessorCount)"
 rm -rf /tmp/w && cp -r /ev0/src-nogrid /tmp/w && cd /tmp/w; make clean >/dev/null 2>&1; $M test_gpt2cu >b_g.log 2>&1 || grep -m3 " error" b_g.log
 ./test_gpt2cu 2>&1 | grep -m2 -iE "assert|abort|overall okay"
 date -Is' ) > $EV/$V.log 2>&1; echo "$V done"; done
