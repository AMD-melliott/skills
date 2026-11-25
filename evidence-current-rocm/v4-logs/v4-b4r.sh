#!/usr/bin/env bash
# Scorer V4/D check for screen P4r: the deliverable is the committed branch in the run's local clone of the
# AMD port. Fresh clone of that branch (committed content only), stock ROCm image, only the prerequisites
# the run's docs name (cmake/ninja/git, which the stock images lack), its documented build commands.
# Tests: cuco -> the project's ctest; rccl-tests -> every *_perf binary, 1 rank, -c 1, all dtypes and ops.
# Usage: v4-b4r.sh <label> <ver: 7.2.1|10.1.0> [diag]   (diag: adds -DBUILD_BENCHMARKS=OFF for cuco, logged separately)
# rocm-systems clones are blobless partial clones that cannot serve a clone, so for nccl the fresh clone is
# GitHub rocm-systems at the run's base commit plus its commits applied with git am; the rccl-tests tree hash
# is checked against the run's branch.
set -u
R2=/data/melliott/moat-testing/round2; L=$1; V=$2; DIAG=${3:-}
case $V in 7.2.1) IMG=rocm/dev-ubuntu-24.04:7.2.1-complete;; *) IMG=rocm/dev-ubuntu-24.04:$V-full;; esac
P=$R2/projects/$L
case $L in
 cuco-B4r-1) SRC=$P/amd-port;;
 cuco-B4r-2) SRC=$P/amd-port/hipCollections;;
 nccl-B4r-1) SRC=$P/_amd/rocm-systems;;
 nccl-B4r-2) SRC=$P/amd-port/rocm-systems;;
esac
SFX=${DIAG:+-diag}; D=$R2/v4/$L-$V$SFX; LOG=$R2/v4/$L-$V$SFX.log
[[ -e $D ]] && { echo "$D exists"; exit 1; }
busy=$(amd-smi process -g 7 --csv 2>/dev/null | awk -F, 'NR>1 && $6+0>0' | wc -l); [[ $busy -eq 0 ]] || { echo "GPU 7 busy"; exit 2; }
BR=$(git -C $SRC branch --show-current); TIP=$(git -C $SRC rev-parse HEAD)
if [[ $L == nccl-* ]]; then
  BASE=$(git -C $SRC merge-base HEAD origin/HEAD 2>/dev/null || git -C $SRC rev-parse HEAD~2)
  PD=$R2/v4/$L-$V$SFX.patches; mkdir -p $PD; git -C $SRC format-patch -q -o $PD $BASE..HEAD
  git clone -q --filter=blob:none --no-checkout https://github.com/ROCm/rocm-systems.git $D || exit 3
  git -C $D sparse-checkout set projects/rccl-tests && git -C $D checkout -q --detach $BASE || exit 3
  git -C $D -c user.name=v4 -c user.email=v4@local am -q $PD/*.patch || exit 3
  T1=$(git -C $D rev-parse HEAD:projects/rccl-tests); T2=$(git -C $SRC rev-parse HEAD:projects/rccl-tests)
  echo "base=$BASE rccl-tests tree fresh=$T1 run=$T2 $([[ $T1 == $T2 ]] && echo MATCH || echo MISMATCH)" > $LOG.pre
  [[ $T1 == $T2 ]] || exit 4
else
  git clone -q --branch "$BR" "$SRC" $D || exit 3
fi
{ echo "deliverable: $SRC branch $BR tip $TIP"; echo "fresh clone tip: $(git -C $D rev-parse HEAD)"; cat $LOG.pre 2>/dev/null; } > $LOG
PRE='(command -v git >/dev/null || (apt-get update -qq && apt-get install -y -qq git >/dev/null 2>&1)); python3 -m pip install -q --break-system-packages --target /tmp/pt "cmake>=3.31,<4" ninja >/dev/null 2>&1; export PATH=/tmp/pt/bin:$PATH PYTHONPATH=/tmp/pt'
SWEEP='cd build && n=0; ok=0; for b in ./*_perf; do n=$((n+1)); out=$($b -b 8 -e 64M -f 4 -c 1 -o all -d all 2>&1); rc=$?; w=$(echo "$out" | grep -c "Out of bounds values : 0 OK"); if [[ $rc -eq 0 && $w -ge 1 ]]; then ok=$((ok+1)); echo "PASS $b"; else echo "FAIL $b rc=$rc"; echo "$out" | grep -iE "wrong|error|abort|fail" | head -8; fi; done; echo "SWEEP $ok/$n binaries pass"'
case $L in
 cuco-B4r-1) CMD="$PRE; cmake -G Ninja -S . -B build -DCMAKE_PREFIX_PATH=/opt/rocm -DCMAKE_HIP_ARCHITECTURES=gfx942 -DBUILD_TESTS=ON -DBUILD_EXAMPLES=ON -DCMAKE_BUILD_TYPE=Release ${DIAG:+-DBUILD_BENCHMARKS=OFF} && cmake --build build -j 64 && cd build && ctest -j8";;
 cuco-B4r-2) CMD="$PRE; cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=/opt/rocm -Drapids-cmake-branch=release/26.10 -DCMAKE_HIP_ARCHITECTURES=gfx942 ${DIAG:+-DBUILD_BENCHMARKS=OFF} && cmake --build build -j 64 && (cd build && ctest -j4)";;
 nccl-B4r-1) CMD="cd projects/rccl-tests && GPU_TARGETS=gfx942 make -j32 NCCL_HOME=/opt/rocm >/dev/null && $SWEEP";;
 nccl-B4r-2) CMD="export LD_LIBRARY_PATH=/opt/rocm/lib; cd projects/rccl-tests && make -j32 GPU_TARGETS=gfx942 >/dev/null && $SWEEP";;
esac
echo "image=$IMG" >> $LOG; echo "cmd=$CMD" >> $LOG; date -Is >> $LOG
( cd $D && /data/melliott/moat-testing/tools/rocm-run --image $IMG bash -lc "$CMD" ) >> $LOG 2>&1; rc=$?
echo "RC=$rc" >> $LOG; date -Is >> $LOG
docker run --rm -v $D:$D $IMG chown -R "$(id -u):$(id -g)" $D >/dev/null 2>&1
echo "$L $V rc=$rc"
