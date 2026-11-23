#!/usr/bin/env bash
# Live view of the round-2 queue: driver status, spend, and the current run's latest activity. Read-only.
R2=/data/melliott/moat-testing/round2
while true; do
  clear
  echo "== round 2 queue  $(date '+%F %T')"
  echo; echo "-- driver status (p45, phase2)"; tail -n 4 $R2/p45.status 2>/dev/null; tail -n 12 $R2/phase2.status 2>/dev/null
  echo; echo "-- spend: $(awk -F'|' 'NR>6 && $5+0>0 {t=$5} END{printf "$%.2f", t+0}' $R2/SPEND.md) total"
  cur=$(ls -td $R2/transcripts/*/ 2>/dev/null | head -1); L=$(basename "$cur")
  if [[ -n $cur && ! -f $cur/exit ]]; then
    echo; echo "-- current run: $L (started $(cat $cur/start 2>/dev/null))"
    python3 - "$cur/transcript.jsonl" <<'PY'
import json, sys
n = 0; ev = []
try:
    for l in open(sys.argv[1]):
        try: d = json.loads(l)
        except Exception: continue
        if d.get('type') != 'assistant': continue
        for c in d['message'].get('content', []):
            if c.get('type') == 'tool_use':
                n += 1; i = c.get('input', {})
                ev.append('  [tool] ' + (i.get('command') or i.get('file_path') or i.get('skill') or json.dumps(i))[:150].replace('\n', ' '))
            elif c.get('type') == 'text' and c['text'].strip():
                ev.append('  >> ' + c['text'].strip()[:300].replace('\n', ' '))
except FileNotFoundError:
    pass
print(f'  tool calls so far: {n}')
print('\n'.join(ev[-14:]))
PY
  else
    echo; echo "-- no run in progress (last: $L)"
  fi
  echo; echo "-- GPU 7"; amd-smi process -g 7 --csv 2>/dev/null | awk -F, 'NR>1 {print "  pid " $3 " vram " $6}'
  sleep 30
done
