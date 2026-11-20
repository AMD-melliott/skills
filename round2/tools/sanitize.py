#!/usr/bin/env python3
"""Label-blind transcript for scoring. Usage: sanitize.py <transcript.jsonl> <out.txt>
Numbered steps: assistant text, tool calls, truncated tool results. Removes the init event (skill list),
the content of every Skill tool result and of every tool call that reads the skill's own files, and any
arm/branch identifiers. Step numbers let a scorer judge ordering (verdict before first edit, matrix
before first build)."""
import json, re, sys

SKILL_PATH = re.compile(r'(tool-results/|\.claude/skills/cuda-to-rocm|round2/arms|armBdi|armA\b|armB\b|/arms/|skills-held)')
SCRUB = [(re.compile(r'round2/arms/arm\w+'), '<skill-dir>'), (re.compile(r'\barm ?(A|B|Bdi)\b'), 'arm ?'),
         (re.compile(r'/home/melliott/\.claude/skills/cuda-to-rocm'), '<skill-dir>'),
         (re.compile(r'round2/(armA|armB|armB-di)'), '<branch>')]
TR = 1500  # chars kept from each tool result

def scrub(s):
    for r, t in SCRUB: s = r.sub(t, s)
    return s

src, out = sys.argv[1], sys.argv[2]
skill_ids = set(); step = 0; lines = []
for raw in open(src):
    try: m = json.loads(raw)
    except Exception: continue
    t = m.get('type')
    if t == 'system': continue
    if t == 'assistant':
        for c in m['message'].get('content', []):
            if c.get('type') == 'text' and c['text'].strip():
                step += 1; lines.append(f'[{step}] ASSISTANT: {scrub(c["text"].strip())}')
            elif c.get('type') == 'tool_use':
                step += 1
                inp = c.get('input', {}); s = json.dumps(inp)
                if c['name'] == 'Skill' or SKILL_PATH.search(s):
                    skill_ids.add(c['id'])
                    lines.append(f'[{step}] TOOL {c["name"]}: [skill access: input and output removed]')
                else:
                    lines.append(f'[{step}] TOOL {c["name"]}: {scrub(s)[:1200]}')
    elif t == 'user':
        cont = m.get('message', {}).get('content', [])
        if isinstance(cont, str): continue
        for c in cont:
            if c.get('type') != 'tool_result': continue
            if c.get('tool_use_id') in skill_ids:
                lines.append('    RESULT: [skill text removed]'); continue
            body = c.get('content')
            if isinstance(body, list): body = '\n'.join(x.get('text', '') for x in body if isinstance(x, dict))
            body = scrub(str(body or ''))
            if len(body) > TR: body = body[:TR // 2] + f'\n...[{len(body) - TR} chars cut]...\n' + body[-TR // 2:]
            lines.append('    RESULT: ' + body.replace('\n', '\n    '))
    elif t == 'result':
        lines.append(f'[END] FINAL MESSAGE: {scrub(str(m.get("result")))}')
open(out, 'w').write('\n'.join(lines) + '\n')
print(f'{step} steps, {len(skill_ids)} skill accesses removed -> {out}')
