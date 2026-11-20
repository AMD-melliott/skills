#!/usr/bin/env bash
# Sequential blind-run driver (round 2 follow-up screens). Same cap/STOP/denial logic as phase1.sh.
# Usage: screen.sh <name> "<label> <arm> <url> <commit> <est-usd>" ...   Status in round2/<name>.status.
set -u
R2=/data/melliott/moat-testing/round2
CAP=150; NAME=$1; shift
st() { echo "$(date -Is) $*" | tee -a $R2/$NAME.status; }
total() { awk -F'|' 'NR>6 && $5+0>0 {t=$5} END{printf "%.2f", t+0}' $R2/SPEND.md; }
for r in "$@"; do
  set -- $r; L=$1; A=$2; U=$3; C=$4; EST=$5
  [[ -f $R2/transcripts/$L/exit ]] && { st "skip $L (done)"; continue; }
  [[ -f $R2/STOP ]] && { st "STOP file present; halting before $L"; exit 0; }
  T=$(total)
  if awk -v t=$T -v e=$EST -v c=$CAP 'BEGIN{exit !(t+e>c)}'; then st "HALT: $T + est $EST would cross cap $CAP (before $L)"; exit 1; fi
  # Per-run hard limit: never more than the room left under the cap, and at most 25.
  MB=$(awk -v t=$T -v c=$CAP 'BEGIN{m=c-t; if(m>25)m=25; printf "%.2f", m}')
  st "start $L arm=$A total_so_far=$T max_budget=$MB"
  MAX_BUDGET=$MB $R2/tools/blind-port2.sh "$A" "$L" "$U" "$C"; rc=$?
  [[ $rc -ne 0 ]] && { st "HALT: harness rc=$rc for $L"; exit 1; }
  read COST TURNS DEN < <(python3 - "$R2/transcripts/$L/transcript.jsonl" <<'PY'
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
PY
)
  NT=$(awk -v t=$T -v c=$COST 'BEGIN{printf "%.2f", t+c}')
  echo "| $L | $A | $COST | $NT |" >> $R2/SPEND.md
  st "end $L exit=$(cat $R2/transcripts/$L/exit) cost=$COST turns=$TURNS outward_denials=$DEN total=$NT"
  [[ $DEN -gt 0 ]] && { st "HALT: outward-facing attempt in $L"; exit 1; }
done
st "$NAME complete"
