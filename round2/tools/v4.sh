#!/usr/bin/env bash
# Scorer V4 check: deliverable = what `git add -A` would capture (none of the runs committed), overlaid on a
# fresh clone of upstream at the pinned commit; fresh stock container per ROCm version; only the documented
# commands, plus the prerequisites the port's own docs name (CMake >= 4 / cmake, ninja via pip into /tmp).
# Usage: v4.sh <label> <ver: 7.2.1|10.1.0|10.2.0>
set -u
R2=/data/melliott/moat-testing/round2; L=$1; V=$2
case $V in 7.2.1) IMG=rocm/dev-ubuntu-24.04:7.2.1-complete;; *) IMG=rocm/dev-ubuntu-24.04:$V-full;; esac
SRC=$R2/projects/$L; D=$R2/v4/$L-$V; LOG=$R2/v4/$L-$V.log
[[ -e $D ]] && { echo "$D exists"; exit 1; }
mkdir -p $R2/v4
busy=$(amd-smi process -g 7 --csv 2>/dev/null | awk -F, 'NR>1 && $6+0>0' | wc -l); [[ $busy -eq 0 ]] || { echo "GPU 7 busy"; exit 2; }
C=$(git -C $SRC rev-parse HEAD); URL=$(git -C $SRC remote get-url origin)
git clone -q "$URL" $D && git -C $D checkout -q --detach $C || exit 3
( cd $SRC && git ls-files -z -co --exclude-standard | rsync -a --from0 --files-from=- ./ $D/ )
( cd $SRC && git ls-files -z -d ) | ( cd $D && xargs -0 -r rm -f )
( cd $D && for x in build* .deps/cpm-cache; do [[ -e $x ]] && ! git ls-files --error-unmatch "$x" >/dev/null 2>&1 && { echo "removed untracked build output: $x"; rm -rf "$x"; }; done ) > $LOG.pre
echo "deliverable files changed vs upstream: $(git -C $D status --short | wc -l)" > $LOG
cat $LOG.pre >> $LOG
PRE='(command -v git >/dev/null || (apt-get update -qq && apt-get install -y -qq git >/dev/null 2>&1)); python3 -m pip install -q --target /tmp/pt "cmake>=4" ninja >/dev/null 2>&1; export PATH=/tmp/pt/bin:$PATH PYTHONPATH=/tmp/pt'
case $L in
 cuco-A1|cuco-A2) CMD="$PRE; cmake --version | head -1; cmake -S . -B build-hip -G Ninja -DCUCO_USE_HIP=ON -DCMAKE_PREFIX_PATH=/opt/rocm -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/clang++ -DCMAKE_HIP_COMPILER=/opt/rocm/llvm/bin/clang++ -DCMAKE_HIP_ARCHITECTURES=gfx942 && cmake --build build-hip -j 64 && ctest --test-dir build-hip -j 8";;
 nccl-A1) CMD="make -j ROCM=1 GPU_TARGETS=gfx942 && make -C verifiable ROCM=1 GPU_TARGETS=gfx942 && tools/run_single_gpu_checks.sh build 64M";;
 nccl-A2) if [[ $V == 7.2.1 ]]; then CMD="make -j HIP=1 BUILDDIR=build-hip && make -C verifiable HIP=1 && hip/run_tests.sh build-hip";
          else CMD="make -j HIP=1 BUILDDIR=build-hip-10.1 && SELF_TEST=none hip/run_tests.sh build-hip-10.1"; fi;;
esac
echo "image=$IMG" >> $LOG; echo "cmd=$CMD" >> $LOG; date -Is >> $LOG
( cd $D && /data/melliott/moat-testing/tools/rocm-run --image $IMG bash -lc "$CMD" ) >> $LOG 2>&1; rc=$?
echo "RC=$rc" >> $LOG; date -Is >> $LOG
docker run --rm -v $D:$D $IMG chown -R "$(id -u):$(id -g)" $D >/dev/null 2>&1
echo "$L $V rc=$rc"
