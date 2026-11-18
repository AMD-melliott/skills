#!/bin/bash
# compare SASS of matching objects; maps .../p3d-gate/new/... to .../p3d-gate/base/...
cd "$(dirname "$0")"; n=0; d=0; e=0
f() { cuobjdump -sass "$1" 2>/dev/null | grep -vE 'Fatbin|code for sm|\.target|arch =|host =|compile_size|identifier' ; }
for o in $(cd new/build && find . -name '*.o' | sort); do
  ob=$(echo "$o" | sed 's#/p3d-gate/new/#/p3d-gate/base/#'); [ -f base/build/$ob ] || { echo "MISSING base $ob"; continue; }
  a=$(f base/build/$ob | md5sum); b=$(f new/build/$o | md5sum); lines=$(f new/build/$o | wc -l)
  n=$((n+1)); [ $lines -gt 0 ] && e=$((e+1)); [ "$a" = "$b" ] || { d=$((d+1)); echo "SASS DIFF: $o"; }
done; echo "objects=$n with_sass=$e sass_diff=$d"
