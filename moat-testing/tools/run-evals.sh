#!/usr/bin/env bash
# Run every prompt in the skill's evals.json in a fresh headless agent, one empty dir each.
# Usage: run-evals.sh <label> [evals.json] [id-regex]  -> /data/melliott/moat-testing/evals/<label>/<id>/
# The skill under test is whatever ~/.claude/skills/moat-cuda-to-rocm points at (the live checkout).
set -u
LABEL=${1:?label}
ROOT=/data/melliott/moat-testing
EV=${2:-$ROOT/skills/skills/moat-cuda-to-rocm/evals/evals.json}
FILT=${3:-.}
OUT=$ROOT/evals/$LABEL
mkdir -p "$OUT"
while read -r id; do
  d=$OUT/$id; mkdir -p "$d/work"
  python3 -c "import json,sys;e=[e for e in json.load(open('$EV'))['evaluations'] if e['id']=='$id'][0];open('$d/prompt.txt','w').write(e['prompt'])"
  ( cd "$d/work" && timeout 1800 claude -p --settings $ROOT/blind-settings.json --strict-mcp-config \
      --allowedTools "Read,Write,Edit,Glob,Grep,Skill,WebSearch,WebFetch" --output-format stream-json --verbose \
      < "$d/prompt.txt" > "$d/transcript.jsonl" 2> "$d/stderr.txt"; echo $? > "$d/exit" ) &
done < <(python3 -c "import json;[print(e['id']) for e in json.load(open('$EV'))['evaluations'] if __import__('re').search('$FILT',e['id'])]")
wait
