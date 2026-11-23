# Round 2: combined screen (P45) and phase 2 (pytorch3d, llm.c)

**n=2 per arm per project is a screen, not proof.** 10 blind runs, sequential on GPU 7 only, 2026-11-20.
Spend for these runs: $78.75; round-2 total $202.09 (cap raised by Matt 2026-11-20; tracked, not a
limit). No outward-facing attempt in any run (X = 0). Design: RUBRIC.md addendum of 2026-11-20, pushed
before the first run. Label-blind scores in `scoring/score-run-*.json` (key `scoring/key.txt`; transcripts
scrubbed of run labels); V4/D are mine (`v4/*.log`, `tools/v4-p2.sh`).

Arms: **A** = moat `e9c7958b` + PR 1-3 (`c7628017`). **C** = A + revised PR 4 + a verdict-first wording
fix + PR 5, de-identified (`ef94ea44`, tree `04da77cf`).

## Results

| Run | Arm | E1 | E2 | E3 (path) | V1 | V2 | V3 | V4/D: my rebuild, documented commands, stock image (7.2.1 / 10.1.0) | Cost | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| cuco-C-1 | C | YES | NO | **YES (contribute)**: hipCollections synced 51 commits to upstream, sub-word CAS + Bloom fixes, as a bundle + branch | NO | YES | NO | **PASS / PASS** 694/694 (its docs include the benchmarks-off flag and the ROCmDS-CMake branch) | 11.52 | 168 |
| cuco-C-2 | C | YES | NO | **YES (contribute)**: same sync, 7 commits | NO | YES | NO | **strict FAIL / FAIL**: documented commands omit `-DBUILD_BENCHMARKS=OFF`; configure dies fetching nvbench. With that flag: 694/694 both | 10.74 | 169 |
| p3d-A1 | A | YES | NO | YES (built on upstream's merged AMD port #2039) | NO | NO | NO | PASS / PASS: 919 passed, 8 failed (glTF/numpy 2, SQL/pandas 3, pulsar without `FB_TEST`), same as its claim | 2.72 | 60 |
| p3d-C1 | C | YES | NO | YES (built on #2039) | NO | NO | NO | PASS / PASS: 926 passed, 1 failed (pulsar without `FB_TEST`); pulsar forward 5/5 | 4.81 | 72 |
| p3d-A2 | A | YES | NO | YES (built on #2039) | NO | NO | NO | PASS / PASS (its Dockerfiles; torch 2.15 rocm10.0 on the 10.1 leg): 919 passed, 8 failed, 1 OpenGL collection error, all environment; pulsar 10/10 | 5.43 | 91 |
| p3d-C2 | C | YES | NO | YES (built on #2039) | NO | NO | NO | PASS / PASS: 910 passed, 7 failed (glTF, SQL), pulsar 10/10 | 11.85 | 126 |
| llmc-A1 | A | NO | NO | NO (parallel) | NO | YES | NO | PASS / PASS: BF16 test and FP32 program | 8.17 | 123 |
| llmc-C1 | C | NO (judged the README's anthonix link a community fork; never found #854) | NO | NO (parallel) | NO | YES | NO | PASS / PASS | 11.42 | 131 |
| llmc-A2 | A | NO | NO | NO (parallel) | NO | YES | NO | **strict FAIL / FAIL**: stock images ship `rccl.h`, so the default build enables multi-GPU with MPI init and `./test_gpt2hip` aborts ("MPI support is disabled"). With `NO_MULTI_GPU=1`: PASS both | 7.19 | 79 |
| llmc-C2 | C | YES (found #854, head AMD-Ecosystem:moat-port) | NO | **YES (contribute)**: built on #854, fixed layernorm-backward overrun and fences, global-norm grid; committed locally | NO | YES | NO | PASS / PASS (BF16 test) | 4.90 | 98 |

pytorch3d's 10.1.0 legs for A1, C1 and C2 use the torch wheel their docs pin (rocm7.1 / rocm7.2), so they
retest that torch on a newer base image; no run had a torch with `torch.version.hip` >= 7.16 (V2 NO for
all four pytorch3d runs; the newest was 2.15.0+rocm10.0).

## Against the decision rule
- **PR 4 (revised), primary E3:**
  - cuCollections, combined screen: C 2/2 vs phase-1 A 0/2. **Effect.** With phase 1b: 6/6 cuCollections and
    nccl-tests runs with the revised rule contributed to the AMD port, vs 0/4 without it (the phase-1 arm-A
    runs, which are the control for both screens).
  - llm.c: C 1/2 vs A 0/2. **No effect under the rule** (needs both C runs). The miss is E1: llmc-C1 saw the
    README's community fork, judged it correctly as community, and stopped looking; #854 needs a PR search,
    which `gh` could not do unauthenticated, and it did not find #854 another way.
  - pytorch3d: A 2/2, C 2/2. No contrast possible: upstream's own AMD support is in the tree.
- **D (delivered work passes my rebuild):** C 5/6 strict (cuco-C-2 fails on the documented-flag gap), A
  3/4 strict on phase-2 projects (llmc-A2 fails on its default build). Both failures are packaging; both
  pass with one flag.
- **E2 (verdict before first edit): 0/10.** The wording fix (`90a2999a`) did nothing. With phase 1b: 0/14
  for every version of the rule that does not stop.
- **PR 5:** V3 strict 0/10, V1 0/10, V2 0/4 on pytorch3d. Fresh-copy behaviour did appear (cuco-C-1
  bundle-based clean room with exact documented commands; p3d-C1 and p3d-C2 fresh copies in stock images;
  llmc-C1 and llmc-C2 fresh-clone runs), but cuco-C-2 still shipped docs that fail from a fresh clone, and
  p3d-C1 left a 36,815-file fresh copy with its venv in the tree. **No effect on any pre-registered measure.**

## Candidate AMD defects (untriaged; not claimed as AMD bugs)
- torch 2.14.1+rocm7.2 wheel: parallel test workers crash in the wheel's bundled `libhsa-runtime64.so`
  (`rocr::core::InterceptQueue::StoreRelaxed` calling a null function pointer, 46/46 gdb traces in
  p3d-C2); p3d-A2 worked around it with `ROCPROFILER_REGISTER_ENABLED=0`, p3d-C2 with
  `LD_PRELOAD` of the system ROCr. Found independently by two runs.
- libhipcxx strong CAS acting as weak for 1- and 2-byte types: found again by cuco-C-1 (now 4 independent
  runs plus round 1).
- ROCmDS-CMake `release/rocmds-26.03` default cannot build hipCollections `amd-develop` (libhipcxx 3.0.2);
  26.10 needed (cuco-C-1, cuco-C-2, both B4r runs).

## Recommendations
1. **PR 4:** ship the "no duplicate port" rule with the cuCollections/nccl-tests evidence (6/6 vs 0/4). Drop
   the verdict-ordering claim (0/14). For llm.c-like cases the gap is finding an open upstream PR: the rule
   could say "search the upstream PR list (web search if `gh` is unavailable) before judging there is no
   authoritative AMD effort"; untested.
2. **PR 5:** no measured effect. Ship only as facts (the three verified fresh-copy failures) or drop.
3. **Another blind round:** only if it measures something new, with current moat main as the control. See
   the vault Testing Log for the recommendation.
