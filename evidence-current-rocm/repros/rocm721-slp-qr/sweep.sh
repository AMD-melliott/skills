#!/usr/bin/env bash
# Version sweep of the QR repro: one image at a time, GPU 7 only via rocm-run. Records pulled images in pulled.txt.
cd /data/melliott/moat-testing/repros/rocm721-slp-qr
for V in 7.2.1-complete 7.2.2-complete 7.2.4-complete 7.1.1-complete 7.0.2-complete 6.4.4-complete 7.14.1-full 10.0.0-full 10.1.0-full 10.2.0-full; do
  I=rocm/dev-ubuntu-24.04:$V
  docker image inspect $I >/dev/null 2>&1 || { docker pull -q $I >/dev/null && echo $I >> pulled.txt; }
  out=$(/data/melliott/moat-testing/tools/rocm-run --image $I bash -lc '
    echo "hip=$(hipconfig --version)";
    for f in "-O1" "-O2" "-O3" "-O3 -fno-slp-vectorize"; do
      hipcc -std=c++17 --offload-arch=gfx942 $f -I warp/native -w -o /tmp/qr qr_repro.hip 2>&1 | tail -2 && echo "[$f] $(/tmp/qr 2>&1 | tail -1)";
    done' 2>&1)
  echo "== $V"; echo "$out"
done
echo SWEEPDONE
