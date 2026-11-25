#!/usr/bin/env bash
# Sequential evidence queue on GPU 7 (one job at a time). Progress in queue.log.
EV=/data/melliott/moat-testing/evidence; T=/data/melliott/moat-testing/round2/tools; cd $EV
log(){ echo "$(date -Is) $*" >> $EV/queue.log; }
while pgrep -f "evidence/pr1-llmc/run.sh|pr1-llmc && ./run.sh" >/dev/null; do sleep 30; done
log "start"
$EV/pr3-llmc/run.sh 7.14.1-full 10.1.0-full 10.2.0-full >> $EV/queue.log 2>&1
$EV/pr5-cuco-ignore/run.sh 10.2.0-full 7.14.1-full >> $EV/queue.log 2>&1
I=rocm/pytorch:rocm10.2.0_ubuntu24.04_py3.12_pytorch_release_2.15.0
docker image inspect $I >/dev/null 2>&1 || { docker pull -q $I >/dev/null && echo $I >> $EV/pulled.txt; }
$EV/pr3-p3d/run.sh $I r102 >> $EV/queue.log 2>&1
for V in 10.2.0 7.14.1; do
  [ $V = 7.14.1 ] && export ROCM_RUN_ARGS="-e LD_LIBRARY_PATH=/opt/rocm/core-7.14/lib:/opt/rocm/lib" || unset ROCM_RUN_ARGS
  for L in cuco-B4r-1 cuco-B4r-2 nccl-B4r-1 nccl-B4r-2; do log "v4-b4r $L $V"; $T/v4-b4r.sh $L $V >> $EV/queue.log 2>&1; done
  for L in cuco-B4r-1 cuco-B4r-2; do log "v4-b4r $L $V diag"; $T/v4-b4r.sh $L $V diag >> $EV/queue.log 2>&1; done
  for L in cuco-C-1 cuco-C-2 llmc-C1 llmc-C2 llmc-A2 p3d-C1 p3d-C2; do log "v4-p2 $L $V"; $T/v4-p2.sh $L $V >> $EV/queue.log 2>&1; done
  for L in cuco-C-2 llmc-A2; do log "v4-p2 $L $V diag"; $T/v4-p2.sh $L $V diag >> $EV/queue.log 2>&1; done
done
log "ALLDONE"
