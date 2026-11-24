# PR 4 and PR 5 evals: main text vs branch text (2026-11-23)

**n=3 per arm per eval; text-only, no GPU.** One fresh headless `claude -p` per run (Opus 5.5), with an empty directory holding the skill as a project skill; tools Read/Write/Edit/Glob/Grep/Skill/WebSearch/WebFetch, no Bash; credentials stripped; auto-memory off. User-level cuda/rocm skills were held aside during the runs and restored afterwards.
- **Old** = moat main `8620918e` (tree `34a82f35`).
- **New** = main merged with `cuda-to-rocm/existing-amd-port` (`d6fa2c6d`) or `cuda-to-rocm/fresh-copy-validation` (`dffade14`).
- `evals/` was removed from every installed tree, so no run could read `expected_behavior`.
- **Grading:** label-blind, by a separate agent, from packets keyed by random run IDs (`evals-pr45/key.txt`, `grading/scores.json`). Spend: $4.16.

| Eval | Old | New | Skill invoked |
|---|---|---|---|
| `authoritative-amd-port-proceed-without-asking` (PR 4) | 3/3 | 3/3 | 6/6 |
| `authoritative-amd-port-single-tree-need` (PR 4) | 2/3 | 3/3 | 6/6 |
| `pr-checklist-port-with-patch-files` (PR 5) | 3/3 | 3/3 | 1/6 (old 1, new 0) |

**Strict readings.** The grader flagged two ambiguous items in the single-tree eval:
- **E2, "even with contributions":** under explicit-wording-only grading, old 56507a and 878b3b fail.
- **E4, proceed rather than ask:** if any approval gate counts as asking, old 56507a and 878b3b and new ad523f fail.

Under both strict readings the result is old 0/3 vs new 2/3. That difference depends on the grader's reading and n=3, so it is not a finding.

## What this means
- **proceed-without-asking:** current main's text already passes. The eval prompt hands the agent the existing-support verdict, which is the step where blind ports went wrong. So this eval cannot reproduce the behaviour PR 4 changed, and it is a regression guard, not a discriminator.
- **The PR 4 blind-port effect was measured against `e9c7958b` + PR 1-3, not current main.** Main has since gained bb61ae96 and later assess-existing-support text, including "contribute the differentiator". Whether current main alone gets the contribute path in a blind port is untested. That is the one open question for PR 4's evidence.
- **single-tree-need:** no clear discrimination; borderline at most. Keep it as a regression guard.
- **PR 5's eval:** the base model handles it with or without the skill. It is a regression guard, as the body already says.
