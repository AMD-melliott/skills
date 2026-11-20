# Round 2 rubric (pre-registered)

Status: frozen 2026-11-19 before the first blind run (pushed to `moat-testing-results`, `round2/RUBRIC.md`).
Not edited after that; any later note goes in a dated addendum below the freeze line.

## Arms
- BASE_SHA: AMD-Ecosystem/moat `e9c7958ba976d3bd99effb735684f1865a3f10be` (main, 2026-11-19).
- Arm A (control): BASE_SHA + PR 1 fault classes + PR 2 7.2.1 SLP miscompile + PR 3 ROCm-version/size
  validation, re-fitted onto the restructured skill (`c7628017`, tree `496c4873`).
- Arm B as run ("Bdi", treatment): arm A + PR 4 existing-port verdict and hard stop + PR 5 matrix-first
  and fresh-clone rules (`e37e7d8e`), plus a TEST-ONLY commit that replaces the project names in the
  treatment text and evals (cuCollections, hipCollections, ROCm-DS, HyperLogLog, dynamic_map, libhipcxx,
  pytorch3d, cuco file names) with generic wording (`e8dec6f5`, tree `0b0293fa`). Decided by Matt
  2026-11-19 so a blind port of a named project is not reading a worked example of itself. The rules are
  verbatim; PR text is unchanged. Arms A and Bdi still share the PR 1-3 text, which names cuCollections
  and libhipcxx (no differential effect).
- Both installed as `~/.claude/skills/cuda-to-rocm`; plugins off, no MCP; `hf-cli` and
  `git-status-review` (user skills, present in round 1 too) listed but not invocable.

## Measures (per run; binary unless stated)

| Measure | Counts as YES when |
|---|---|
| E1 | The transcript shows the agent found the authoritative AMD effort: cuCollections -> ROCm/hipCollections; NVIDIA/nccl-tests -> ROCm/rccl-tests; llm.c -> AMD-Ecosystem/llm.c `moat-port` or karpathy/llm.c#854; pytorch3d -> upstream's merged HIP support (#2039). |
| E2 | A written verdict (notes, plan, summary or a message) naming that effort, with an authoritative/community judgement, timestamped in the transcript BEFORE the first edit to a project source/build file. |
| E3 | It did NOT build a parallel port of what the AMD effort covers. Record the path taken: `contribute` (work delivered against the AMD effort), `validate` (the AMD effort built and tested as is), `stop` (asked/ended without porting), `parallel` (ported anyway; E3 = NO), with its stated reason. |
| V1 | A written validation matrix (ROCm releases x archs x sizes; for torch, the torch build per ROCm leg) before the first build command. |
| V2 | Its own build+test on a ROCm >= 10.1 leg (10.1.0 or 10.2.0; record which). For pytorch3d: with a torch whose `torch.version.hip` is >= 7.16. |
| V3 | It rebuilt from a fresh clone/worktree of its committed result in a fresh container from a stock image, with exactly its documented commands, and ran the tests. A wrapper script, exported env var or reused build dir = NO. |
| V4 | **Scorer check (primary outcome for PR 5).** I clone the deliverable as committed, in a stock image, run only its documented commands, no wrapper, on 7.2.1 and 10.1.0. YES if it builds and its tests pass on both. If the agent did not commit, the deliverable is what `git add -A` would capture (tracked + untracked-not-ignored files); record "not committed" separately. V4 applies to whatever the agent delivered (a port, a contribution patch against the AMD effort, or a validation harness). |
| Q | Test pass counts (nccl-tests: every `*_perf` binary the port builds, run on the 1 visible GPU with data checking on, `#wrong` 0 and "Out of bounds values : 0 OK"; cuCollections: ctest) on 7.2.1 and 10.1.0 (and 10.2.0 if its image runs on GPU 7: recorded, not part of any decision), nvcc gate result, cost, wall time, turns. Q is reported, not compared across arms when the arms delivered different kinds of things. |
| X | Outward-facing attempts (push, PR/issue/comment, fork, upload): count and quote. Any attempt = stop the round. |

## Decision rule
- A rule "shows an effect" if arm B beats arm A on its primary measure in BOTH B runs and NEITHER A run
  matches. Primary measures: E3 for the hard stop (PR 4); V4 for the fresh-clone rule (PR 5); V2 for the
  matrix rule (PR 5, phase 2 pytorch3d).
- n=2 per arm is a screen, not proof; every summary says so.
- No effect -> propose trimming the PR to its verified facts, or dropping it. Do not keep text that only
  reads better.
- Arm B worse than arm A on anything arm A got right (Q, V-measures, faults anticipated) -> report it
  prominently.

## Scoring procedure
- Label-blind: each transcript goes to a fresh scoring subagent with the arm label removed, every Skill
  tool result and every Read of a skill file replaced by `[skill text removed]`, and RUBRIC.md as its
  only instructions. It scores E1-E3, V1-V3 and X. Residual leak, accepted and noted: the agent's own
  words can quote the rule it followed.
- I score V4 and Q myself, then reconcile with the subagent's scores; disagreements are listed, not
  silently resolved.

## Run plan
- Phase 1: NVIDIA/cuCollections @ 403526d, order A, Bdi, A, Bdi; then NVIDIA/nccl-tests @ afd59abab774
  (v2.21.1, 2026-10-05), order A, Bdi, A, Bdi. Stop for review after both (Matt, 2026-11-19).
  nccl-tests is named nowhere in either arm; its upstream does not mention AMD. Single GPU only: the
  container exposes one GPU, so multi-rank runs are limited to that GPU.
- Phase 2 (only on Matt's go): pytorch3d @ ddfc551 and llm.c @ f1e2ace, A, B, A, B each.
- Per run: fresh clone at the pinned commit, generic request (`prompts/request-generic.txt`), neutral env
  notes unchanged (`prompts/env-notes.md`), GPU 7 only, checked free before each run.
- Spend: running total in SPEND.md; hard cap $150 including eval re-runs; stop before a run that would
  cross it.

---
## Addendum 2026-11-19 (after the phase-1 blind runs; scorer judgement, not a rubric change)
- V4 deliverable: cuco-A1's `git add -A` would capture 14,494 files, almost all untracked build output
  (`build-hip/`, `build-hip-7.2.1/`, `build-cuda/`, `.deps/cpm-cache/`). Reusing those trees would break the
  "fresh build" condition, so v4.sh deletes untracked top-level `build*` dirs and `.deps/cpm-cache` before
  building, and the would-be-committed build output is recorded as a separate packaging defect.
- Arm-B runs that stopped to ask (all four in phase 1) delivered nothing: V1-V4 and Q are N/A for them.
- 2026-11-19: stock ROCm images lack git, which upstream cuCollections' CPM/rapids-cmake needs; v4.sh installs git in the container for cuCollections (a prerequisite of upstream, not of the port). First attempt logs kept in v4/attempt1-nogit/.

---
## Addendum 2026-11-19, follow-up screens (written before any follow-up run; Matt approved the plan 2026-11-19)

**Shared baseline.** The phase-1 arm-A runs (cuco-A1, cuco-A2, nccl-A1, nccl-A2) are the control for both
screens below; arm A is not re-run. Same skill tree (`496c4873`), project commits, request and env notes.
Harness differences from phase 1, both outside the skill: Claude Code auto-memory is off
(`autoMemoryEnabled: false` and `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`; nccl-A2 used it in phase 1), and each
run has `--max-budget-usd` = min(25, room left under the cap). Phase-1 harness kept as
`tools/blind-port2-phase1.sh`. Runs are sequential on GPU 7 only. The baseline is from a few hours
earlier on the same model and harness; time drift is an accepted, noted confound.

**Screen P5: PR 5 alone.** Arm A5 = arm A + PR 5 (`7b89b0a4`), plus a test-only commit replacing the
project names in PR 5's text (the same substitutions as `e8dec6f5`, restricted to PR 5's files):
`6f40980d`, tree `f5d69a4a`. A5 differs from the phase-1 Bdi tree only by PR 4. Runs: cuCollections
@ 403526d, cuco-A5-1 and cuco-A5-2.
- Primary measure: **V3** (A: 0/2 on cuCollections). Effect = A5 2/2.
- Why not V4: cuco-A1 already passed V4, so under the decision rule ("neither A run matches") V4 cannot
  show an effect on this baseline. V4 is reported (A: 1/2); A5 worse than 1/2 is a regression to report.
- Also reported: V1 (matrix before first build; A 0/2), V2, Q, the packaging defects (ignored files,
  committed build output), cost and turns.

**Screen P4r: PR 4 revised.** Arm B4r = arm A + the revised PR 4 (prepared by a separate session from
`PR4-REVISION-BRIEF.md`, no PR 5), plus the same kind of test-only de-identification. SHAs recorded here
before its first run. Runs: cuco-B4r-1, cuco-B4r-2, then nccl-B4r-1, nccl-B4r-2 (budget permitting).
- Primary: **E3** (A 0/4), with path `contribute` or `validate` counting YES and `stop` counting NO for
  this screen (the revision exists to remove the stop). Effect = B4r YES in both runs of a project.
- Co-primary, **D (delivered)**: the run's deliverable for its chosen path passes V4 (for a contribution:
  my fresh rebuild of the AMD port clone plus its commits, its documented commands; for a validation: its
  documented build-and-test commands reproduce its reported result). A's V4 is the comparison (cuco 1/2,
  nccl 2/2). B4r passing E3 but failing D in both runs is reported as "no working default yet".
- Reported: E1, E2, V1-V3, Q, cost, turns.

**Cap.** Stop before any run where total + 20 would cross $150; each run's hard limit is above.
