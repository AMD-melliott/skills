#!/usr/bin/env bash
# Launch a blind porting agent in a project dir. Usage: blind-port.sh <projdir> <runlabel> "<request>"
set -u
ROOT=/data/melliott/moat-testing
P=$1; LABEL=$2; REQ=$3
T=$ROOT/transcripts/$LABEL; mkdir -p "$T"
{ echo "$REQ"; echo; cat $ROOT/prompts/env-notes.md; } > "$T/prompt.txt"
cd "$P" && date -Is > "$T/start" && \
timeout 21600 claude -p --settings $ROOT/blind-settings.json --strict-mcp-config \
  --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Skill,WebSearch,WebFetch,TodoWrite" \
  --output-format stream-json --verbose < "$T/prompt.txt" > "$T/transcript.jsonl" 2> "$T/stderr.txt"
echo $? > "$T/exit"; date -Is > "$T/end"
