#!/usr/bin/env bash
# PR 5: the round-1 cuCollections port configured from (a) what `git ls-files -co --exclude-standard` lists, overlaid on a
# fresh upstream clone at 403526d, and (b) the same plus the two ignored patch files. Documented configure command.
EV=/data/melliott/moat-testing/evidence/pr5-cuco-ignore; P=/data/melliott/moat-testing/projects/cuCollections; RR=/data/melliott/moat-testing/tools/rocm-run
for V in "$@"; do for VAR in committed with-ignored; do D=$EV/$V-$VAR; rm -rf $D; git clone -q https://github.com/NVIDIA/cuCollections.git $D && git -C $D checkout -q --detach 403526d
 ( cd $P && git ls-files -co --exclude-standard -z | grep -zv '^\.port_work/' ) | ( cd $P && rsync -a --from0 --files-from=- ./ $D/ )
 [ $VAR = with-ignored ] && mkdir -p $D/cmake/hip/patches && cp $P/cmake/hip/patches/*.diff $D/cmake/hip/patches/
 { echo "variant=$VAR ignored-by-upstream:"; (cd $P && git status --ignored --short cmake/hip | grep '^!!'); (cd $P && git check-ignore -v cmake/hip/patches/*.diff); ls $D/cmake/hip/patches/ 2>&1; } > $EV/$V-$VAR.log
 ( cd $D && $RR --image rocm/dev-ubuntu-24.04:$V bash -lc 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null; apt-get install -y -qq git ninja-build python3-pip >/dev/null; pip3 install -q --break-system-packages "cmake>=3.30"; cmake -S . -B build-hip -G Ninja -DCUCO_USE_HIP=ON -DCMAKE_HIP_ARCHITECTURES=gfx942 -DCMAKE_PREFIX_PATH=/opt/rocm -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/clang++ -DCMAKE_HIP_COMPILER=/opt/rocm/llvm/bin/clang++ 2>&1 | grep -E "patch|Error|error|Configuring done|Generating done" | head -8; echo "configure rc=${PIPESTATUS[0]}"' ) >> $EV/$V-$VAR.log 2>&1
 docker run --rm -v $D:$D rocm/dev-ubuntu-24.04:10.2.0-full chown -R $(id -u):$(id -g) $D >/dev/null 2>&1; echo "$V $VAR done"; done; done
