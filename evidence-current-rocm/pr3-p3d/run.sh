#!/usr/bin/env bash
# PR 3: round-1 pytorch3d port on rocm/pytorch for the current ROCm (torch built for that ROCm). GPU 7 only.
EV=/data/melliott/moat-testing/evidence/pr3-p3d; RR=/data/melliott/moat-testing/tools/rocm-run; IMG=$1; TAG=$2
( cd $EV/src && $RR --image $IMG bash -lc 'export HOME=/tmp; pip install -q iopath fvcore scipy imageio matplotlib pillow parameterized omegaconf hydra-core visdom lpips accelerate tqdm "pandas<3" sqlalchemy plotly pytest >/dev/null 2>&1; echo "pip rc=$?"; python -c "import numpy;print(\"numpy\",numpy.__version__)"; PY=python3 bash _p3d.sh '$TAG'' ) > $EV/$TAG.log 2>&1; echo "$TAG done"
