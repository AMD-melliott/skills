# cuCollections: blind port, run 1

- **Upstream:** NVIDIA/cuCollections `403526d` (2026-11-17). **Skill:** `0774273`. **Env notes:** neutral.
  **Request:** generic (`prompts/request-generic.txt`).
- **Run:** 2026-11-17 16:19-17:15 (56 min), 219 turns, $13.42, exit 0. Transcript
  `transcripts/cuCollections-run1/`; project `projects/cuCollections/`; scoring copy `tmp/cuco-score/`.

## What the agent built

- **Build:** an opt-in `-DCUCO_USE_HIP=ON` path that enables the HIP language. Shim headers sit on the HIP
  include path only.
- **Dependencies:** CCCL maps to libhipcxx (`ROCm/libhipcxx` amd-develop `832dc407f`, fetched by CPM with
  two local patches), rocThrust and hipCUB.
- **Changes:** 24 tracked files (+283/-157) and an untracked `cmake/hip/`.
- **Library source edits:** neutral for nvcc. They add `template`/`typename` keywords, `static_cast<void>`,
  one include, one `__host__`, and HIP branches.

## Independent verification (clean copy, my own build, GPU 7)

| | ROCm 7.2.1 | ROCm 10.1.0 |
|---|---|---|
| Configure from the tracked + untracked-non-ignored files | **FAILS**: `Couldn't find patch file .../libhipcxx_atomic_alignment.diff` | same |
| Build (with the two ignored patch files copied in) | clean, 0 errors | clean, 0 errors |
| ctest | **693/693** | **693/693** |

- **nvcc 12.8 gate** (sm_70;90, benchmarks off, upstream `-Werror=all-warnings`): all 402 targets built,
  0 errors.
- **Port defect, not caught by the agent:** upstream `.gitignore:55` has `*.diff`, so both
  `cmake/hip/patches/*.diff` are invisible to `git status`. A commit, PR or fresh clone of this port
  would not configure. The agent's own validation ran in its working tree, where the files exist.

## Claims checked with my own repros

| Claim | Repro | Result |
|---|---|---|
| libhipcxx `compare_exchange_strong` is weak at block/device scope | `repros/libhipcxx-cas/cas.hip` | **Confirmed**: 1-byte 75% and 2-byte 50% spurious failures on both ROCm versions, for amd-develop `832dc407f` **and for ROCm 10.1.0's bundled `hipccl` (CCCL 3.0.2)**. Raw strong builtin: 0. Agent's patch: 0. **Genuine AMD library bug; flagged, not filed.** See `repros/libhipcxx-cas/README.md` |
| `atomic_ref` on an 8-byte, 4-byte-aligned struct fails | `repros/libhipcxx-align/align.hip` | **Confirmed**: "unsupported cmpxchg" (7.2.1); `ld.lld: ... instruction alignment 4 is smaller than the required 8-byte alignment` (10.1.0). Patched version gives the correct `{1,2}`. NVIDIA libcu++ compiles it |
| HLL bias tables (`__device__ constexpr`) read as zeros by the host | `repros/device-constexpr-host/dc2.hip` (+ `dc2.cu`) | **Confirmed, but only through a pointer** (`.data()` from a `__host__ __device__` helper): HIP host reads `0 0 0 0` (-O0) or `0 9.2e18 0 0` (-O2), while nvcc 12.8 reads `1.5 2.5 3.5 4.5`. Direct constant indexing (`dc.hip`) is correct on HIP, which hides the bug in small tests |

## Behaviour against the skill

| Item | Observed |
|---|---|
| Existing-port check | Done **before** porting. It found **ROCm/hipCollections** (AMD official, ROCm-DS) and the community repo `cuda2rocm`, and recorded both with verdicts. **But it then built a parallel port.** The skill says a mature separate AMD project (ROCm-DS-style) means skip, or contribute the differentiator to it (its own example is RAPIDS → ROCm-DS). The agent's rationale (hipCollections is a hard fork of an older upstream with no hyperloglog or dynamic_map; "the in-place additive port is the right shape for an upstream PR") is reasonable, but it did not address the skill's rule. The ideal outcome was to surface that conflict, or to frame the work as a differentiator for hipCollections (newer upstream, HLL, the libhipcxx fixes). **Adherence miss, not a gap in the text.** |
| ROCm versions | Both, from the start |
| Largest sizes | Upstream's large cases (HLL 2^25-2^28, multi-million keys) run |
| Wave64 | Kept `warp_size() == 32` as a *logical* tile size (correct). 64-bit tile ballot handled with `__ffs` overloads |
| Root-causing | Strong. It diagnosed the CAS bug from 11 failing `int8_t`/`int16_t` cases (`count == 398` vs 400) down to a header line |
| CUDA gate | Done (12.8, `-Werror=all-warnings`). I re-ran it: pass |
| Packaging check | **Missed**: ignored patch files |
| `fork()` | Uses `fork()` in `debug_assert_test` (a child launches a kernel that asserts) and it passes. The skill's line "HIP after `fork()` crashes in the child" did not bite here, presumably because the parent has not touched HIP before forking. Not investigated further |

## Gaps → commits (edit worktree, `moat-testing`)

| Gap | Commit |
|---|---|
| Host reads of a `__device__` constexpr table through a pointer get HIP's zeroed shadow (nvcc: real values) | caf605b |
| libhipcxx: strong CAS is weak for 1-/2-byte; under-aligned 8-byte `atomic_ref` fails to link | f7438a8 |
| Upstream ignore rules can hide port files; validate from a fresh clone | f698bb2 |

Each adds an unhinted eval. Discrimination test at n=3 is below.

## Not testable here

Same as before: no wave32/RDNA, no NVIDIA runtime, no multi-GPU. Benchmarks (nvbench) were not ported.

## Discrimination test (n=3, old = 0774273, new = f698bb2 with all three edits)

| Eval | Old skill | New skill | Decision |
|---|---|---|---|
| `review-host-finalizer-device-tables` | 3/3 find the host-shadow cause | 3/3 | **held** (caf605b → local `held/cuCollections`) |
| `review-small-key-atomic-insert-libhipcxx` | 3/3 raise weak-CAS only as a **hypothesis to check** ("if the emulation behaves like a weak CAS", "cannot rule out"); one ranks another cause first | 3/3 name the libhipcxx defect, the offending overloads and the measured rates | **kept: 72a85eb**. Eval tightened: hedging is now unexpected |
| `pr-checklist-port-with-patch-files` | 3/3 spot the ignored patches (the prompt's `git status`/`ls` reveal them) | 3/3 | **held** (f698bb2). The blind port really did miss this, but the eval cannot show the edit helps. Kept as a process candidate for Matt |

## Validation (step D)

### Blind re-port, run 2 (skill 72a85eb, clean clone)

- **Run:** 2026-11-17 17:40-18:41 (60 min), 202 turns, $18.80. Transcript `transcripts/cuCollections-run2/`.
- **My verification:** a clean copy of tracked plus untracked-non-ignored files only, so ignored files
  could not mask a gap.
  - **702/702** ctest on ROCm 7.2.1 and on 10.1.0: upstream's 694 plus 8 regression cases it added.
  - nvcc 12.8: 405/405 targets with upstream `-Werror=all-warnings`.

| Item | Run 1 (0774273) | Run 2 (72a85eb) |
|---|---|---|
| libhipcxx weak strong-CAS | found **from 11 failing tests**, root-caused, header patched | **anticipated**: CAS smoke test at step 108, cuco-side atomic wrapper at step 115, **before the first ctest (step 138)**. Added `duplicate_small_keys_test` |
| libhipcxx source | amd-develop `832dc407f` + 2 `.diff` patches (gitignored) | `release/26.10` `90b6a2b` (3.4.0), with no patches; the fix lives in cuco's own `detail/utility/atomic.cuh` |
| Packaging | the port does not configure from a clean commit | clean copy builds and passes |
| hipCollections | found, recorded, then a parallel port anyway | **same** |
| Extra stress | upstream large cases | plus a 4M-insert contention stress (1-/2-/16-byte) and HLL p18 on the 64 KiB-LDS fallback |

**Reading:** the kept edit moved discovery from "after tests fail" to "before the first test" (n=1 each).
The existing-port decision is consistent across both runs: the agent records hipCollections as
authoritative and still builds a parallel port, which goes against the skill's "do not duplicate AMD's
own work". The skill text is clear, so this is a behaviour pattern to raise with Matt, not a text gap.

### Full eval re-run (72a85eb)

- **Triggers:** all 10 should-trigger evals invoked the skill; the 3 negatives did not.
- **Graded evals:** keyword checks match the previous runs. **No regressions.**
