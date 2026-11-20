# Round 2, phase 1 results (cuCollections + nccl-tests; arms A vs Bdi; n=2 per arm per project)

**n=2 per arm is a screen, not proof.** Spend: $52.09 of the $150 cap (8 blind runs + one $0.12 harness smoke test;
no eval re-runs). No outward-facing attempt in any run (X = 0 everywhere; the harness also had credentials removed).

Arms: A = moat main `e9c7958b` + PR 1-3 re-fitted (`c7628017`); Bdi = A + PR 4 + PR 5, with project names in the
treatment text replaced by generic wording for testing only (`e8dec6f5`). Rubric: `RUBRIC.md` (frozen before the first
run; addenda below the freeze line). Label-blind scores: `scoring/score-run-*.json` (key: `scoring/key.txt`); V4/Q
are mine (`v4/*.log`).

| Run | Arm | E1 | E2 | E3 (path) | V1 | V2 | V3 | V4 (my fresh rebuild, 7.2.1 / 10.1.0) | Cost | Turns |
|---|---|---|---|---|---|---|---|---|---|---|
| cuco-A1 | A | NO | NO | NO (parallel; never searched) | NO | YES | NO | **PASS / PASS**: ctest 693/693 both. But `git add -A` would commit 14,494 files of build output (3 build trees, 572 MB CPM cache); removed for the check | 13.15 | 181 |
| cuco-A2 | A | YES | NO | NO (parallel; cloned hipCollections as a reference, no stated reason) | NO | YES | NO | **FAIL / FAIL**: `cmake/hip/patches/*.diff` ignored by upstream `.gitignore:55 *.diff`, so the deliverable lacks them; configure aborts "could not apply libhipcxx-strong-cas.diff". Round 1's defect, repeated | 12.88 | 167 |
| nccl-A1 | A | NO (borderline: cloned ROCm/rccl-tests only to copy its fp8 handling, never called it AMD's port) | NO | NO (parallel) | NO | YES | NO | **PASS / PASS**: 11 binaries ALL PASSED | 14.41 | 165 |
| nccl-A2 | A | NO | NO | NO (parallel; never searched) | NO | YES | NO | **PASS / PASS**: 34/34 checks | 10.44 | 126 |
| cuco-B1 | Bdi | YES | YES | YES (**stop**; recommended option 3, a parallel port, because the request says keep the CUDA build and hipCollections is HIP-only) | N/A | N/A | N/A | N/A (nothing delivered) | 0.27 | 7 |
| cuco-B2 | Bdi | YES | YES | YES (**stop**; recommended option 1, contribute) | N/A | N/A | N/A | N/A | 0.28 | 8 |
| nccl-B1 | Bdi | YES (found the move to ROCm/rocm-systems `projects/rccl-tests`) | YES | YES (**stop**; recommended contribute) | N/A | N/A | N/A | N/A | 0.24 | 7 |
| nccl-B2 | Bdi | YES | YES | YES (**stop**; recommended contribute) | N/A | N/A | N/A | N/A | 0.30 | 8 |

Scorer prerequisites, recorded in the rubric addenda: cuCollections needs git and CMake >= 4 (both upstream
prerequisites), installed inside the stock container; untracked `build*` trees and `.deps/cpm-cache` removed so the
check is a fresh build.

## Against the pre-registered decision rule
- **PR 4 hard stop, primary measure E3: shows an effect on both projects** (B 2/2 and A 0/2 on each; 4/4 vs 0/4 overall).
  E1 4/4 vs 1/4 and E2 4/4 vs 0/4 move with it.
- **But every B run ignored the rule's own fallback** ("With no one to ask, take one of the first two and write the gap
  up"). All four ended a headless run with a question after 7-8 turns, so arm B delivered nothing: no contribution, no
  validation of the AMD port, no gap write-up beyond the message. That is a regression in what an autonomous run
  produces, relative to arm A's working (if duplicate) ports.
- **The recommendation inside the stop is not reliable:** cuco-B1 recommended the parallel port, on a reasonable reading
  of the request ("keep the CUDA build unchanged" in this repo is something a separate HIP-only fork cannot give).
- **PR 5 (matrix-first, fresh clone): not measurable in this design.** Arm B never reached a build, because PR 4's stop
  pre-empts it. The arm-A data shows the problem PR 5 targets is real and recurring: V3 0/4 (no fresh-clone rebuild in any
  run), V1 0/4, one V4 failure (cuco-A2, ignored patches) and one would-be commit of 14k build files (cuco-A1).

## Other observations
- Arm A's existing-port check is weak without PR 4: only 1 of 4 runs found the AMD effort it was told to look for, and
  that one ignored it. Round 1's two cuCollections runs both found hipCollections, so this varies run to run.
- Both nccl A runs independently report two RCCL defects on gfx942, each with a standalone probe (not re-run or triaged
  by me): single-rank fp8 avg/premulsum aborts (7.2.1 and 10.1), and single-rank send/recv of >= ~1-2 GiB is wrong with
  ROCm 7.2.1's RCCL (fixed in 10.1). Flagged as candidates; per the triage rule, not claimed as AMD bugs yet.
- nccl-A2 found that ROCm 10.1's RCCL `nccl_device.h` `#define`s `WARP_SIZE 64`, which collides with a project
  constant.
- Harness: nccl-A2 wrote Claude Code auto-memory files to `~/.claude/projects/<its project path>/memory/`. That path is
  per-run, so nothing leaked between runs, but blind runs should disable auto-memory.
- ROCm 10.2.0 is published and runs on GPU 7; no run used it (the neutral notes list 7.2.1 and 10.1.0 only).
