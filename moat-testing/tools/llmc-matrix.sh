#!/usr/bin/env bash
# Build and run llm.c's GPU test matrix (inside a ROCm container). Prints one line per run.
set -o pipefail
make clean >/dev/null 2>&1
for p in BF16 FP32; do
  make test_gpt2cu USE_HIP=1 HIP_ARCH=gfx942 PRECISION=$p >build_$p.log 2>&1 || { echo "BUILD FAIL $p"; grep -m5 ' error' build_$p.log; continue; }
  for a in "" "-r 0" "-r 2" "-w 0" "-b 32"; do
    out=$(./test_gpt2cu $a 2>&1); echo "$p [$a] $(echo "$out" | grep -E 'overall okay' | tail -1) | $(echo "$out" | grep -c 'NOT OK') NOT-OK lines"
  done
done
make test_gpt2fp32cu USE_HIP=1 HIP_ARCH=gfx942 >build_fp32cu.log 2>&1 && echo "test_gpt2fp32cu: $(./test_gpt2fp32cu 2>&1 | grep -E 'overall okay' | tail -1)" || { echo "BUILD FAIL test_gpt2fp32cu"; grep -m5 ' error' build_fp32cu.log; }
