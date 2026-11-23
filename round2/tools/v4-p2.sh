#!/usr/bin/env bash
# Scorer V4/D check for screen P45 and phase 2. Deliverable:
#  - committed branch (cuco-C-*: the run's hipCollections clone/bundle; llmc-C2: its rocm-port branch), or
#  - uncommitted: what `git add -A` would capture, overlaid on a fresh upstream clone at the pinned commit,
#    minus untracked virtualenvs (pyvenv.cfg), nested git repos and top-level build*/ dirs (logged).
# Stock ROCm image; only the run's documented commands (incl. the prerequisites its docs install).
# Usage: v4-p2.sh <label> <ver: 7.2.1|10.1.0> [diag]  (diag: adds the one flag the docs omit, logged separately)
set -u
R2=/data/melliott/moat-testing/round2; L=$1; V=$2; DIAG=${3:-}
case $V in 7.2.1) IMG=rocm/dev-ubuntu-24.04:7.2.1-complete;; *) IMG=rocm/dev-ubuntu-24.04:$V-full;; esac
P=$R2/projects/$L; SFX=${DIAG:+-diag}; D=$R2/v4/$L-$V$SFX; LOG=$R2/v4/$L-$V$SFX.log
[[ -e $D ]] && { echo "$D exists"; exit 1; }
busy=$(amd-smi process -g 7 --csv 2>/dev/null | awk -F, 'NR>1 && $6+0>0' | wc -l); [[ $busy -eq 0 ]] || { echo "GPU 7 busy"; exit 2; }
mkdir -p $R2/v4
overlay() {  # $1 upstream url, $2 commit
  local C=$(git -C $P rev-parse HEAD)
  git clone -q "$1" $D && git -C $D checkout -q --detach $C || exit 3
  ( cd $P && python3 - <<'PY'
import os, subprocess
out = subprocess.run(['git','ls-files','-z','-co','--exclude-standard'], capture_output=True).stdout.split(b'\0')
keep, drop = [], set()
for f in (x.decode() for x in out if x):
    parts = f.split('/')
    bad = None
    for i in range(1, len(parts)):
        d = '/'.join(parts[:i])
        if os.path.exists(os.path.join(d, 'pyvenv.cfg')) or os.path.exists(os.path.join(d, '.git')) or (i == 1 and d.startswith('build')):
            bad = d; break
    if f.endswith('/') and os.path.exists(os.path.join(f, '.git')): bad = f
    if bad: drop.add(bad)
    else: keep.append(f)
open('/tmp/v4keep.lst','w').write('\0'.join(keep))
print('excluded from overlay (venvs, nested repos, build dirs):', ', '.join(sorted(drop)) or 'none')
print('files overlaid:', len(keep))
PY
  ) >> $LOG.pre
  ( cd $P && rsync -a --from0 --files-from=/tmp/v4keep.lst ./ $D/ )
  ( cd $P && git ls-files -z -d ) | ( cd $D && xargs -0 -r rm -f )
}
: > $LOG.pre
case $L in
 cuco-C-1) git clone -q -b sync-upstream-dev $P/port-tools/hipcollections-sync-upstream-dev.bundle $D || exit 3;;
 cuco-C-2) git clone -q -b sync-upstream-876 $P/amd-port/hipCollections $D || exit 3;;
 llmc-C2)  git clone -q -b rocm-port $P $D || exit 3;;
 p3d-*)    overlay https://github.com/facebookresearch/pytorch3d.git;;
 llmc-*)   overlay https://github.com/karpathy/llm.c.git;;
esac
{ echo "label=$L ver=$V deliverable tip/base: $(git -C $D rev-parse HEAD)"; echo "files changed vs HEAD: $(git -C $D status --short | wc -l)"; cat $LOG.pre; } > $LOG

APT='export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null'
P3DENV='apt-get install -y -qq python3-venv python3-dev python3-pip git ninja-build >/dev/null && python3 -m venv /tmp/venv && . /tmp/venv/bin/activate'
LLMPRE='(command -v curl >/dev/null && command -v wget >/dev/null) || apt-get install -y -qq curl wget >/dev/null'
case $L in
 cuco-C-1) CMD="$APT; apt-get install -y -qq git python3-pip ninja-build >/dev/null && pip3 install -q --break-system-packages cmake && export RAPIDS_CMAKE_SCRIPT_BRANCH=release/26.10 RAPIDS_CMAKE_BRANCH=release/26.10 && cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=/opt/rocm -DCMAKE_HIP_ARCHITECTURES=gfx942 -DBUILD_TESTS=ON -DBUILD_EXAMPLES=ON -DBUILD_BENCHMARKS=OFF && cmake --build build -j 48 && cd build && ctest --timeout 1800";;
 cuco-C-2) CMD="$APT; (command -v git >/dev/null || apt-get install -y -qq git >/dev/null); python3 -m pip install -q --break-system-packages 'cmake>=3.30,<4' ninja && cmake -S . -B build -G Ninja -DCMAKE_HIP_ARCHITECTURES=gfx942 ${DIAG:+-DBUILD_BENCHMARKS=OFF} && cmake --build build -j && cd build && ctest -j8 --timeout 900";;
 p3d-A1) CMD="$APT; $P3DENV && pip install -q torch torchvision --index-url https://download.pytorch.org/whl/rocm7.1 && pip install -q iopath numpy matplotlib imageio tqdm pytest pytest-timeout scipy hydra-core omegaconf pandas sqlalchemy tabulate lpips plotly PyOpenGL visdom accelerate && PYTORCH_ROCM_ARCH=gfx942 MAX_JOBS=64 FORCE_CUDA=1 python setup.py build_ext --inplace >/dev/null && python -c 'import torch;print(\"torch\",torch.__version__,torch.version.hip)' && python -m pytest tests -q --timeout=900 2>&1 | tail -15";;
 p3d-C1) CMD="$APT; $P3DENV && pip install -q torch==2.14.1 torchvision --index-url https://download.pytorch.org/whl/rocm7.2 && pip install -q 'numpy<2.3' 'pandas<3' iopath scipy imageio matplotlib pillow parameterized fvcore omegaconf ninja setuptools wheel pytest pyopengl plotly 'sqlalchemy>=2.0' hydra-core visdom lpips accelerate tqdm && PYTORCH_ROCM_ARCH=gfx942 MAX_JOBS=32 python setup.py build_ext --inplace >/dev/null && python -c 'import torch;print(\"torch\",torch.__version__,torch.version.hip)' && python -m pytest tests -q 2>&1 | tail -15; FB_TEST=1 python -m pytest tests/pulsar/test_forward.py -q 2>&1 | tail -3";;
 p3d-A2) DF=$D/.port-env/Dockerfile; [[ $V == 7.2.1 ]] || DF=$D/.port-env/rocm10/Dockerfile
         ( docker build -q -t moat-v4-p3d-a2:$V -f $DF $(dirname $DF) ) >> $LOG 2>&1 || echo "docker build failed" >> $LOG
         IMG=moat-v4-p3d-a2:$V; PRELOAD=""; [[ $V == 7.2.1 ]] && PRELOAD="export ROCPROFILER_REGISTER_ENABLED=0;"
         CMD="export PATH=/opt/venv/bin:\$PATH; PYTORCH_ROCM_ARCH=gfx942 MAX_JOBS=32 python setup.py build_ext --inplace >/dev/null && python -c 'import torch;print(\"torch\",torch.__version__,torch.version.hip)' && $PRELOAD python -m pytest tests -n 16 -q 2>&1 | tail -15; FB_TEST=1 python -m pytest tests/pulsar -q 2>&1 | tail -3";;
 p3d-C2) CMD="$APT; $P3DENV && pip install -q torch==2.14.1 torchvision --index-url https://download.pytorch.org/whl/rocm7.2 && pip install -q iopath numpy pytest pytest-xdist imageio matplotlib tqdm scipy pillow fvcore hydra-core visdom lpips accelerate sqlalchemy omegaconf pandas plotly && export PYTORCH_ROCM_ARCH=gfx942 && python setup.py build_ext --inplace >/dev/null && python -c 'import torch;print(\"torch\",torch.__version__,torch.version.hip)' && export LD_PRELOAD=/opt/rocm/lib/libhsa-runtime64.so.1 && python -m pytest tests -n 16 -q --ignore=tests/pulsar 2>&1 | tail -15; unset LD_PRELOAD; FB_TEST=1 python -m pytest tests/pulsar -q 2>&1 | tail -3";;
 llmc-A1) CMD="$APT; $LLMPRE; ./dev/download_starter_pack.sh >/dev/null 2>&1; make train_gpt2hip test_gpt2hip >/dev/null && make train_gpt2fp32hip test_gpt2fp32hip >/dev/null && ./test_gpt2hip | tail -4; echo BF16_RC=\${PIPESTATUS[0]}; ./test_gpt2fp32hip | tail -3; echo FP32PROG_RC=\${PIPESTATUS[0]}";;
 llmc-C1) CMD="$APT; $LLMPRE; ./dev/download_starter_pack.sh >/dev/null 2>&1; make train_gpt2hip test_gpt2hip train_gpt2fp32hip test_gpt2fp32hip profile_gpt2hip >/dev/null && ./test_gpt2hip | tail -4; echo BF16_RC=\${PIPESTATUS[0]}; ./test_gpt2fp32hip | tail -3; echo FP32PROG_RC=\${PIPESTATUS[0]}";;
 llmc-A2) CMD="$APT; $LLMPRE; ./dev/download_starter_pack.sh >/dev/null 2>&1; make ${DIAG:+NO_MULTI_GPU=1} test_gpt2hip train_gpt2hip test_gpt2fp32hip train_gpt2fp32hip profile_gpt2hip >/dev/null && ./test_gpt2hip | tail -4; echo BF16_RC=\${PIPESTATUS[0]}; ./test_gpt2fp32hip | tail -3; echo FP32PROG_RC=\${PIPESTATUS[0]}";;
 llmc-C2) CMD="$APT; $LLMPRE; ./dev/download_starter_pack.sh >/dev/null 2>&1; make USE_HIP=1 NO_MULTI_GPU=1 NO_USE_MPI=1 train_gpt2cu test_gpt2cu >/dev/null && ./test_gpt2cu | tail -4; echo BF16_RC=\${PIPESTATUS[0]}";;
esac
echo "image=$IMG" >> $LOG; echo "cmd=$CMD" >> $LOG; date -Is >> $LOG
( cd $D && timeout 10800 /data/melliott/moat-testing/tools/rocm-run --image $IMG bash -lc "$CMD" ) >> $LOG 2>&1; rc=$?
echo "RC=$rc" >> $LOG; date -Is >> $LOG
docker run --rm -v $D:$D rocm/dev-ubuntu-24.04:7.2.1-complete chown -R "$(id -u):$(id -g)" $D >/dev/null 2>&1
echo "$L $V rc=$rc"
