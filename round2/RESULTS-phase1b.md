# Round 2, phase 1b: PR 5 alone (P5) and PR 4 revised (P4r)

**n=2 per arm per project is a screen, not proof.** Spend for 1b: $71.25 (6 blind runs); round-2 total
$123.34 of the $150 cap. No outward-facing attempt in any run (X = 0). All runs sequential on GPU 7 only.
Control for both screens = the phase-1 arm-A runs (not re-run; see the RUBRIC.md addendum of
2026-11-19 for the design, written and pushed before these runs). Harness change vs phase 1: auto-memory
off, per-run `--max-budget-usd`. Label-blind scores in `scoring/score-run-*.json` (key: `scoring/key.txt`);
V4/D are mine (`v4/*.log`).

## Screen P5: arm A + PR 5 (matrix-first, fresh-clone rule), cuCollections

| Run | Arm | E1 | E2 | E3 | V1 | V2 | V3 (strict) | Fresh-copy check it actually did | V4 (my rebuild, 7.2.1 / 10.1.0) | `git add -A` | Cost |
|---|---|---|---|---|---|---|---|---|---|---|---|
| cuco-A1 | A | NO | NO | parallel | NO | YES | NO | none (working tree, reused build dirs, derived images) | PASS / PASS 693 | 14,494 files (build output) | 13.15 |
| cuco-A2 | A | YES | NO | parallel | NO | YES | NO | in-place rebuild after deleting the build dir | **FAIL / FAIL** (`*.diff` patches ignored) | small | 12.88 |
| cuco-A5-1 | A5 | YES | NO | parallel | NO | YES | NO (not committed; ran via a script) | copy of `git ls-files -co --exclude-standard` (what a commit captures), stock 7.2.1 and 10.1.0 images, the script runs exactly the README commands: 688/688 both | PASS / PASS 688 | 315 files, clean | 12.87 |
| cuco-A5-2 | A5 | YES | YES (thin) | parallel | NO | YES | NO (not committed; image from its own Dockerfile; ROCM_RUN_ARGS) | clone at base + its diff + untracked files, image from its documented Dockerfile: 698/698; caught and fixed a consumer-build doc bug | PASS / PASS 698 | 51,300 files (build trees, scratch) | 14.51 |

- **Primary (V3, strict): A 0/2, A5 0/2. No effect under the pre-registered rule.**
- **What the strict measure misses (listed as a disagreement, not resolved):** both A5 runs did a
  rebuild from a copy of exactly what a commit would capture, in fresh containers, with their documented
  commands. Neither A run did. Both A5 runs named their patch files `.patch` and cited upstream's
  `*.diff` ignore rule, which is the defect that failed cuco-A2. They miss strict V3 on "not committed"
  and "run via a script", which the request never asked for (no run in any arm committed).
- **V4: A 1/2, A5 2/2.** Not an effect under the rule (cuco-A1 also passed); no regression.
- **V1 (matrix first): 0/2 in both arms.** The matrix half of PR 5 shows nothing.
- **Not prevented:** untracked build output (A5-2, as A1). The fresh-copy rule checks that the copy
  builds, not what a commit of the working tree would sweep in.

## Screen P4r: arm A + revised PR 4 (no stop; default = contribute or validate)

| Run | Arm | E1 | E2 | E3 (path) | V1 | V2 | V3 | D: my rebuild of the deliverable (7.2.1 / 10.1.0) | Cost |
|---|---|---|---|---|---|---|---|---|---|
| cuco-B4r-1 | B4r | YES | NO | **YES (contribute)**: hipCollections synced to upstream #876 (51 commits behind), HIP fixes, 5 commits | NO | YES | NO | **strict FAIL / FAIL**: documented commands omit `-DBUILD_BENCHMARKS=OFF`, which its wrapper sets; configure fails fetching hipBench. With that one flag: PASS 700/700 both | 15.42 |
| cuco-B4r-2 | B4r | YES | NO | **YES (contribute)**: 47 upstream commits + 6 HIP fixes, 53 commits | NO | YES | NO | **strict FAIL / FAIL**, same cause (its wrapper sets the flag). With it: PASS 689/689 both | 9.70 |
| nccl-B4r-1 | B4r | YES (found the move to rocm-systems) | NO | **YES (contribute)**: upstream 2.19.7-2.21.1 fixes, `comm_ops_perf`, rpath fix, 2 commits | NO | YES | NO | PASS / PASS: fresh clone + its commits (tree hash matches), 9/12 binaries in my all-dtype sweep; the 3 failures are fp8 aborts that unmodified rccl-tests at the same base also has (both ROCm versions); all non-fp8 dtypes pass | 10.73 |
| nccl-B4r-2 | B4r | YES | NO | **YES (contribute)**: 4 upstream fixes, `comm_ops_perf`, 2 commits | NO | YES | NO | PASS / PASS, same as above | 8.02 |

- **Primary E3: B4r 4/4 (2/2 on each project) vs A 0/4. Shows an effect under the rule.**
- **Co-primary D: nccl 2/2 (A: 2/2); cuco strict 0/2 (A: 1/2), 2/2 with one documented-flag fix.** The
  cuco failures are packaging (wrapper-only flag), the defect class PR 5 targets; PR 5 was not in this
  arm. The code itself passes on both releases.
- **Regression: E2 0/4** (phase-1 Bdi: 4/4). The verdict exists, but in PORT_SUMMARY at the end; no run
  wrote it before its first edit. The stop-and-ask version produced the verdict as its stop message; the
  revision lost the ordering. Suggested one-line fix (untested): "write the verdict in your first message,
  before any edit".
- Deliverables are committed branches in local clones of the AMD port, inside the project directory; the
  requested repo is unchanged (the CUDA build is untouched by construction). Nothing pushed.
- Cost and turns are in line with arm A ($8-15, 109-188 tool calls): the revision does real work.

## Other observations
- **Candidate AMD defects, untriaged (not claimed as AMD bugs):** libhipcxx `compare_exchange_strong`
  behaving as weak for 1- and 2-byte types (found independently by both cuco-B4r runs with a reproducer
  and a patch, and by round-1/cuco-A2 as `libhipcxx-strong-cas.diff`); rccl-tests `all_reduce_bias`
  failing on ROCm 7.2.1 (nccl-B4r-2); RCCL fp8 aborts in all_reduce/reduce with `-d all` (pre-existing
  at base, both releases; also reported by both phase-1 nccl runs). ROCmDS-CMake 26.10 pins a hipBench
  branch `release/26.10` that does not exist (both cuco-B4r runs).
- **Scoring blind leak, phase 1 and the first P5 scoring:** project paths carried run labels
  (`cuco-A1`, `cuco-B4r-1`), which hint at the arm. `tools/sanitize.py` now replaces them; all six 1b runs
  were (re)scored from clean transcripts. Phase-1 scores were made with the leak; the measures they
  decided (E1-E3 there) are objective enough that I do not expect a change, but they were not re-run.
- Fresh-clone rebuild for nccl: the agents' rocm-systems clones are blobless partial clones that cannot
  serve a clone, so V4 used GitHub at the base commit plus their commits via `git am`, checking the
  `projects/rccl-tests` tree hash against the run's branch (match in all four).

## Recommendations
1. **PR 4 (revised):** shows an effect on its primary measure and now delivers tested work. Before
   proposing: restore verdict-first ordering (E2) with one sentence, and consider pairing it with PR 5's
   fresh-clone rule, which would likely have caught both cuco packaging failures. A re-screen of that
   combination needs 2 cuco runs (~$25-30); the remaining $26.66 covers only one under the cap rule, so it
   needs a cap decision from you.
2. **PR 5:** no effect on its pre-registered measures (V3 strict, V1). The fresh-copy behaviour it asks
   for did appear (2/2 vs 0/2) and V4 went 1/2 -> 2/2, so trim it to the fresh-copy rule (drop the
   matrix-first half, which moved nothing) and say "fresh copy of what a commit would capture", which is
   what the runs did, rather than requiring a commit.
3. Phase 2 (llm.c, pytorch3d) is still not run; the remaining budget does not cover it.
