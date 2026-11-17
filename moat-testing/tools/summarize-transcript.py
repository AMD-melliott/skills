#!/usr/bin/env python3
"""Summarize a claude stream-json transcript: skill invocations, skill reference reads, tool counts, final result."""
import json, sys, collections
p = sys.argv[1]
tools = collections.Counter(); skills = []; reads = []; result = None; meta = {}
for line in open(p):
    try: m = json.loads(line)
    except Exception: continue
    if m.get('type') == 'assistant':
        for c in m['message'].get('content', []):
            if c.get('type') == 'tool_use':
                tools[c['name']] += 1
                i = c.get('input', {})
                if c['name'] == 'Skill': skills.append(i.get('skill'))
                s = json.dumps(i)
                if 'moat-cuda-to-rocm' in s and c['name'] in ('Read', 'Bash', 'Grep'):
                    reads.append((c['name'], (i.get('file_path') or i.get('command') or i.get('pattern') or '')[:160]))
    elif m.get('type') == 'result':
        result = m.get('result'); meta = {k: m.get(k) for k in ('num_turns', 'duration_ms', 'total_cost_usd', 'is_error')}
print('META', json.dumps(meta)); print('SKILLS', skills); print('TOOLS', dict(tools))
for r in reads: print('SKILLREF', r)
if '--result' in sys.argv: print('RESULT\n', result)
