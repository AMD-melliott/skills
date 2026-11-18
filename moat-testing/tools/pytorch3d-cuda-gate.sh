#!/bin/bash
# inside a CUDA+torch image: build base and new with FORCE_CUDA, dump SASS per object, compare. arg: tag
T=$1; cd "$(dirname "$0")"; export HOME=/tmp FORCE_CUDA=1 TORCH_CUDA_ARCH_LIST="8.0;9.0" MAX_JOBS=48
python -c "import torch;print('torch',torch.__version__,'cuda',torch.version.cuda)"
for s in base new; do (cd $s && rm -rf build && python setup.py build_ext --inplace > ../$s-$T.log 2>&1; echo "$s build rc=$?"); done
[ -d base/build ] && [ -d new/build ] || exit 0; ./cmp.sh; exit 0
n=0; d=0; for o in $(cd new/build && find . -name '*.o' | sort); do
  a=$(cuobjdump -sass base/build/$o 2>/dev/null | grep -vE 'Fatbin|code for sm|\.target|arch =|host =|compile_size|identifier' | md5sum); b=$(cuobjdump -sass new/build/$o 2>/dev/null | grep -vE 'Fatbin|code for sm|\.target|arch =|host =|compile_size|identifier' | md5sum)
  n=$((n+1)); [ "$a" = "$b" ] || { d=$((d+1)); echo "SASS DIFF: $o"; }
done; echo "objects=$n sass_diff=$d"
