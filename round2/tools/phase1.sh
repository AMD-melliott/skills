#!/usr/bin/env bash
# Phase 1 driver: sequential blind runs, spend ledger, stop conditions. Status in round2/phase1.status.
set -u
R2=/data/melliott/moat-testing/round2
CAP=150
CUCO=https://github.com/NVIDIA/cuCollections.git;  CUCO_C=403526d
NCCL=https://github.com/NVIDIA/nccl-tests.git;     NCCL_C=afd59abab774a6a4b492eb344bd0c845a0b7bb4d
# label arm url commit worst-case-estimate-usd
RUNS=(
 "cuco-A1 A $CUCO $CUCO_C 30"  "cuco-B1 Bdi $CUCO $CUCO_C 30"
 "cuco-A2 A $CUCO $CUCO_C 30"  "cuco-B2 Bdi $CUCO $CUCO_C 30"
 "nccl-A1 A $NCCL $NCCL_C 15"  "nccl-B1 Bdi $NCCL $NCCL_C 15"
 "nccl-A2 A $NCCL $NCCL_C 15"  "nccl-B2 Bdi $NCCL $NCCL_C 15"
)
st() { echo "$(date -Is) $*" | tee -a $R2/phase1.status; }
total() { awk -F'|' 'NR>6 && $5+0>0 {t=$5} END{printf "%.2f", t+0}' $R2/SPEND.md; }

for r in "${RUNS[@]}"; do
  set -- $r; L=$1; A=$2; U=$3; C=$4; EST=$5
  [[ -f $R2/transcripts/$L/exit ]] && { st "skip $L (done)"; continue; }
  [[ -f $R2/STOP ]] && { st "STOP file present; halting before $L"; exit 0; }
  T=$(total)
  if awk -v t=$T -v e=$EST -v c=$CAP 'BEGIN{exit !(t+e>c)}'; then st "HALT: $T + est $EST would cross cap $CAP (before $L)"; exit 1; fi
  st "start $L arm=$A total_so_far=$T"
  $R2/tools/blind-port2.sh "$A" "$L" "$U" "$C"; rc=$?
  [[ $rc -ne 0 ]] && { st "HALT: harness rc=$rc for $L"; exit 1; }
  read COST TURNS DEN < <(python3 - "$R2/transcripts/$L/transcript.jsonl" <<'EOF'
import json,sys,re
cost=0;turns=0;bad=0
for l in open(sys.argv[1]):
    try:d=json.loads(l)
    except: continue
    if d.get('type')=='result':
        cost=d.get('total_cost_usd') or 0; turns=d.get('num_turns') or 0
        for p in d.get('permission_denials') or []:
            c=json.dumps(p.get('tool_input',{}))
            if re.search(r'git push|gh (pr|issue|repo|api)|docker (push|login)|upload',c): bad+=1
print(f"{cost:.2f} {turns} {bad}")
EOF
)
  NT=$(awk -v t=$T -v c=$COST 'BEGIN{printf "%.2f", t+c}')
  echo "| $L | $A | $COST | $NT |" >> $R2/SPEND.md
  st "end $L exit=$(cat $R2/transcripts/$L/exit) cost=$COST turns=$TURNS outward_denials=$DEN total=$NT"
  [[ $DEN -gt 0 ]] && { st "HALT: outward-facing attempt in $L"; exit 1; }
done
st "phase 1 complete"
