#!/bin/bash
# Build pytorch3d's extension and run its test suite in the current container. arg: tag
T=$1; PY=${PY:-python}; cd "$(dirname "$0")"; export HOME=/tmp PYTORCH_ROCM_ARCH=gfx942 MAX_JOBS=48
$PY -c "import torch;print('torch',torch.__version__,'hip',torch.version.hip)"
git clean -fdxq -e '_*' -e .port pytorch3d build 2>/dev/null
$PY setup.py build_ext --inplace > _build-$T.log 2>&1; echo "build rc=$?"; grep -c ' error' _build-$T.log
PYTORCH3D_NO_TEST_OPENGL=1 $PY -m pytest -q -p no:cacheprovider tests --ignore=tests/test_opengl_utils.py > _test-$T.log 2>&1; echo "pytest rc=$?"; tail -1 _test-$T.log
FB_TEST=1 $PY -m pytest -q -p no:cacheprovider tests/pulsar > _pulsar-$T.log 2>&1; tail -1 _pulsar-$T.log
PYTHONPATH=$PWD $PY .port/large_sizes.py > _large-$T.log 2>&1; echo "large rc=$?"; tail -2 _large-$T.log
