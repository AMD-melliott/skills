#!/usr/bin/env bash
# Follow the phase-2 rebuild queue: one line per rebuild (result so far), then the live tail of the current log.
# Read-only. Usage: v4-watch.sh [seconds between refreshes, default 20]
V4=/data/melliott/moat-testing/round2/v4
ORDER="cuco-C-1 cuco-C-2 llmc-A1 llmc-C1 llmc-A2 llmc-C2 p3d-A1 p3d-C1 p3d-A2 p3d-C2"
while true; do
  clear; echo "== phase-2 rebuilds  $(date '+%F %T')"; cur=""
  for L in $ORDER; do for V in 7.2.1 10.1.0; do
    f=$V4/$L-$V.log
    if [[ ! -f $f ]]; then s="queued"
    elif grep -q '^RC=' $f; then
      s="done $(grep '^RC=' $f | tail -1) | $(grep -hE 'tests passed|passed,|BF16_RC|FP32PROG_RC|docker build failed' $f | tail -3 | tr '\n' ' ' | cut -c1-110)"
    else s="RUNNING since $(sed -n '/^cmd=/{n;p}' $f | cut -c12-19)"; cur=$f; fi
    printf '  %-9s %-7s %s\n' $L $V "$s"
  done; done
  if [[ -n $cur ]]; then echo; echo "-- tail of $(basename $cur)"; tail -n 15 $cur | cut -c1-200; fi
  echo; echo "-- GPU 7"; amd-smi process -g 7 --csv 2>/dev/null | awk -F, 'NR>1 {print "  pid " $3 " vram " $6}'
  sleep ${1:-20}
done
