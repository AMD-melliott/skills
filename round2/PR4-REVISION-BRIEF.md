# Brief: revise PR 4 (existing-port verdict) so unattended runs do real work

You are revising one skill change in a local clone of AMD-Ecosystem/moat. No GPU work, no blind
runs, no pushes: you only prepare local commits and a short report. Matt Elliott reviews the result.

## Context (read these)
- `/data/melliott/moat-testing/round2/RESULTS-phase1.md`: the phase-1 screen. Read the "Against the
  pre-registered decision rule" section.
- The PR 4 commit as re-fitted onto current moat: `git -C /data/melliott/moat-testing/round2/moat show 025e7519`
  (SKILL.md paragraph, assess-existing-support.md paragraph, one eval).
- The four arm-B final messages: in each `transcripts/<run>/transcript.jsonl` under
  `/data/melliott/moat-testing/round2/` (runs cuco-B1, cuco-B2, nccl-B1, nccl-B2), the `"type":"result"`
  event's `result` field. The request they got was exactly:
  "Port this CUDA project to ROCm/HIP so it builds and its tests pass on this MI300X; keep the CUDA build
  unchanged." plus `/data/melliott/moat-testing/prompts/env-notes.md`.
- `ARMS.md` in the same directory: conventions for this clone (generated SKILL index, evals ordering,
  the word "porter" is rejected by the gate, the codex workaround for the gate).

## What went wrong
All four arm-B runs found the AMD port and wrote a good verdict, then ended a headless run with a
question after 7-8 turns, delivering nothing. Each ignored the rule's own fallback ("With no one to ask,
take one of the first two and write the gap up"): an agent cannot tell that no one will answer, so a
rule whose default action depends on that never fires. One run (cuco-B1) recommended the parallel port
because the request says "keep the CUDA build unchanged" and the AMD fork is HIP-only.

## What to change (the policy Matt approved stays; make it work)
1. Keep the verdict-before-code paragraph as is (it worked: 4/4).
2. Replace "stop and ask before writing port code" with: write the verdict and the path you are taking
   where the user will see it first, then take that path in the same run without waiting for an answer.
   The user can redirect; ending the turn with a question is not the default. (If the user is actively
   in the conversation and has said to check in, asking is fine; say that briefly, do not make it the rule.)
3. The default path when the verdict names an authoritative AMD port: contribute what that port lacks
   (the gap against current upstream: missing features, missing upstream fixes) and validate it on the GPU;
   or, if the gap is too large for one run, validate the AMD port as it is and write the gap up. The
   deliverable is real work: a local clone of the AMD port, inside the working directory, with commits,
   built and tested on the GPU, plus the summary saying where the work is and what is left.
4. Say how to read a request constraint like "keep the CUDA build unchanged": it limits how THIS repo may
   change. It does not require a second port; leaving this repo unchanged satisfies it. Porting this repo
   anyway is for a stated need the AMD port cannot meet even with contributions (example: the user
   explicitly needs one source tree that builds for both vendors). Then say so in the verdict, and still
   use the AMD port as the reference for fixes it already found.
5. Keep it short. The current SKILL.md paragraph is ~6 lines; stay near that. Matching edit to the
   assess-existing-support.md paragraph ("stop and put the choice to the user" no longer matches).
6. Update the PR 4 eval(s) so they expect the new behaviour (verdict, then proceed on the contribute or
   validate path; NOT end the turn asking). Keep the regression-guard eval.
7. Rewrite the commit message body accordingly. Evidence paragraph: add the phase-1 result in one or two
   plain sentences (4/4 verdicts and no parallel port, but all four ended with a question and delivered
   nothing; one recommended the parallel port on the "keep the CUDA build" reading). Keep "Authored with
   Claude." and no Co-Authored-By trailer, as in the other commits.

## Deliverables (local only)
- In `/data/melliott/moat-testing/round2/moat`: branch `round2/armB4r` from `round2/armA` (c7628017),
  one commit = revised PR 4 (real project names, as a PR would carry). Then a second, TEST-ONLY commit on a
  branch `round2/armB4r-di` that replaces the test-project names in the PR 4 text and evals with generic
  wording, using the same substitutions as commit `e8dec6f5` (for example "Two independent ports of one
  CUDA library both found AMD's own, separately named port of it"). No cuCollections, hipCollections,
  ROCm-DS, HyperLogLog, dynamic_map, nccl-tests, rccl-tests, RCCL-tests names in the -di text.
- Use a new worktree (`git worktree add`), not the main checkout (other worktrees share this clone).
- Equivalent revision for the fork branch, which predates moat's restructure: create local branch
  `pr4-rev-fork` from `fork/moat-pr/existing-port-verdict` (2c62f93f) and add ONE new commit on top that makes the
  same text change in that branch's file layout. Do not rebase or amend 2c62f93f. Do not push.
- Gates must pass on both armB4r and armB4r-di:
  `CODEX_HOME=$(mktemp -d) MOAT_LOCAL_TOOLS=1 uv run --python 3.13 python utils/check.py skills harness-adapters jargon`
  (on the fork branch, run whatever gate that older tree supports and say which).
- `/data/melliott/moat-testing/round2/PR4-REVISION.md`: before/after text, commit SHAs and tree SHAs,
  gate output, and anything you could not do.

## Rules
- Do not push anything, anywhere. The clone's push URL is disabled; leave it that way.
- No GPU, no containers, no `claude -p` runs, no changes under `~/.claude/`.
- Nothing outward-facing: no issues, PRs, comments, forks.
- Do not modify branches other than the three named above.
