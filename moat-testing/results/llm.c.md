# llm.c — iteration 1 (blind port, unmodified skill)

| | |
|---|---|
| Upstream | https://github.com/karpathy/llm.c @ `f1e2ace651495b74ae22d45d1723443fd00ecd3a` (2025-05-10) |
| Skill under test | upstream amd/skills `3e41c08` (unmodified) |
| Agent | fresh headless `claude -p` (Opus 5.5), plugins off, only the skill; request: "Port this CUDA project to ROCm/HIP so it builds and its tests pass on this MI300X; keep the CUDA build unchanged." + operational env notes (`prompts/env-notes.md`) |
| Transcript | `transcripts/llm.c-run1/` (`transcript.jsonl`, `timeline.txt`), agent summary `projects/llm.c/PORT_SUMMARY.md` |
| Wall clock / turns / cost | 24 min 48 s (08:27:52-08:52:40), 102 turns, $5.35 |
| Validation-bar gaps | **No wave32 (RDNA), no Windows, no NVIDIA runtime, no multi-GPU** on this host. Nothing here claims them. |

## Strategy

- Chose the Strategy-A shape for a Makefile project with the **shim-header method**:
  `llmc/hip_compat/` (11 headers, 320 lines) shadowing `cuda_runtime.h`, `cublas_v2.h`,
  `cublasLt.h` (-> hipBLASLt), `cooperative_groups*.h`, `nvtx3`, `nccl.h` (-> RCCL); an opt-in
  `USE_HIP=1` block in the Makefile with arch autodetect via `rocm_agent_enumerator` and no pinned
  default. **Right call**, and the minimal-footprint form the skill recommends.
- Warp model: keeps llm.c's 32-lane *logical* warps. The shim `#define`s HIP's `__shfl*_sync` to
  wrappers that ignore the (32-bit) mask and default `width = 32`. Coherent with the skill's
  "width-32 logical warp ops are arch-agnostic" line, and it avoids touching call sites (which the
  skill's own 64-bit-mask advice would require). It does override HIP builtins by macro and drops
  HIP's mask check entirely. Built and passed on both 7.2.1 and 10.1.
- Read only one reference file (`strategy-a-cmake.md`). Never opened `fault-classes.md`,
  `validation.md` or `assess-existing-support.md`.

## Existing-port check: partial

First command was the skill's README grep, which printed README:206, the link to
`anthonix/llm.c` ("support for AMD devices, such as the 7900 XTX"). The agent never mentioned it,
ran no PR or web search, and recorded no authoritative-vs-community verdict. The skill uses this
exact case as its worked example ("karpathy/llm.c links anthonix/llm.c ... missing it cost one full
wasted port ... A repo that LINKS platform forks rather than merging them does not want an upstream
platform PR"), but only inside `references/assess-existing-support.md`. Porting from scratch was
still defensible (community fork, consumer-GPU focus, and the request said to port), but the call
and its consequence for upstreaming were not made.

## Faults

| Fault | When found | Covered by skill? |
|---|---|---|
| `*_sync` 32-bit masks, `WARP_SIZE 32`, `cg::reduce`/`plus`/`greater` absent in HIP 7.2, `__ldcs`/`__stcs`/`__stcg` generic overloads absent, cuBLASLt -> hipBLASLt mapping, `-lineinfo` | before building (grep + header reading) | masks/warp yes; the rest no (mechanical) |
| `global_norm.cuh` `assert(gx*gy < 1024)`: blocks = `maxThreadsPerMultiProcessor * multiProcessorCount / 512` = 2048*304/512 = **1216** on MI300X | runtime, first test run | **no** |
| `layernorm_backward_kernel10` last-block reduction with no `__threadfence()`: stale partial sums -> `Nondeterminism! Loss mismatch at step 1: 6.937172889709473 vs 6.884676456451416`; earlier also wrong `ln2w` grads | runtime, first test run | **no** |
| `train_gpt2_fp32.cu` `matmul_backward_bias_kernel4` uses hardware `warpSize` as column-group width while the grid assumes 32 -> GPU memory access fault at T=1024, `TENSOR NOT OK` (bias grads) at T=64 | runtime (found with `AMD_SERIALIZE_KERNEL=3 AMD_LOG_LEVEL=3`) | yes, the "never hardcode / warp geometry" class, inverse shape |
| host `max(float, float)` in `test_gpt2.cu` truncating the "% of max error" printout | grep, while debugging tolerances | yes |
| `hipProfilerStart/Stop` return not-supported (ROCm 7), aborting `train_gpt2cu` under `cudaCheck` | runtime | no |
| `cublasSetMathMode(TF32)` NOT_SUPPORTED on rocBLAS backend | runtime | no (shim falls back to default math) |
| **Missed:** `cg::plus`/`less`/`greater` stand-ins collide with HIP 7.16 (ROCm 10.1) -> `test_gpt2fp32cu` does not build on ROCm 10.1 | not found (agent validated on 7.2.1 only) | **no** |
| **Missed:** 64 KiB LDS cap. `cudaFuncSetAttribute(MaxDynamicSharedMemorySize, > 64 KiB)` fails on gfx942 AND sets the last error, so llm.c's `cudaCheck(cudaGetLastError())` aborts before its fallback kernel. Any model with C >= 1639 (FP32) or C >= 3277 (BF16) dies at `layernorm.cuh:453` | not found (tests only use GPT-2 124M, C=768) | **no** (known gap 3) |

Tolerances: the agent loosened ROCm-only FP32 gradient/logit/loss tolerances (1e-6 -> 3e-5 grad
floor, 1e-3 -> 2e-3 logits, 1e-5 -> 1e-4 loss) and BF16 `ln2w` 5e-2 -> 6e-2, all under
`__HIP_PLATFORM_AMD__`. Its evidence is decent triage: hipBLASLt FP32 GEMM vs a double reference
(~1e-7 rel, true FP32), the upstream CPU implementation failing the same 13/16 tensors at the 1e-6
floor, `-ffp-contract=on` making no difference. BF16 `lnfw` sits at 99.5% of its unchanged
tolerance. **Flag for Matt:** acceptable as a ROCm-only deviation, but it is a judgement call a
maintainer may push back on.

## Independent verification (mine, scoring copy `tmp/llm.c-score`)

| Check | ROCm 7.2.1 | ROCm 10.1.0 |
|---|---|---|
| `test_gpt2cu` BF16, args `""`, `-r 0`, `-r 2`, `-w 0`, `-b 32` | 5/5 `overall okay: 1` | 5/5 `overall okay: 1` |
| `test_gpt2cu` FP32, same 5 | 5/5 | 5/5 |
| `test_gpt2fp32cu` | `overall okay: 1` | **BUILD FAIL**: `reduce.h:16: redefinition of 'plus'` (also `less`, `greater`) |
| Fence A/B: port with only `layernorm.cuh` reverted to upstream, `test_gpt2cu` BF16 x3 | **0/3** (`Nondeterminism! Loss mismatch at step 1`) | **0/3** |
| LDS: `layernorm_forward` via the port, FP32, C=768 / C=1920 (smem 30,720 / 76,800 B) | ok / **abort `layernorm.cuh:453 invalid argument`** | same |
| LDS: real `train_gpt2cu -e d60` FP32 (C=1920) | **abort `layernorm.cuh:453`** | not run |

Reference: llm.c's own CPU/PyTorch-derived expected values in `test_gpt2.cu` (debug state from the
starter pack). No NVIDIA run is possible here for a side-by-side.

## Footprint and CUDA gate

- 7 tracked files changed, +107/-16 (`Makefile` +50, `README.md` +12, `global_norm.cuh`,
  `layernorm.cuh`, `mfu.h`, `test_gpt2.cu`, `train_gpt2_fp32.cu`) plus new `llmc/hip_compat/` (320
  lines). The `.cuh` edits change CUDA source, but as fixes that are valid on CUDA (fence;
  block-count cap, a no-op wherever the assert held; `warpSize` -> 32, identical where warpSize is
  32). Not a byte-identical passthrough; a behaviour-preserving one on NVIDIA.
- **nvcc gate (mine): PASS.** `nvidia/cuda:12.8.1-devel`, sm_90, all 5 targets build (compile +
  link) for pristine and ported trees, 0 errors, same 2 warnings; `make -n` nvcc command lines
  byte-identical for BF16 and FP32. Compile only, nothing run.

## SKILL GAPS

1. **Missing fault class: cross-block visibility needs a device fence on multi-XCD parts.**
   No entry for "last block reduces everyone's partials" (`atomicInc` flag, no `__threadfence()`).
   Evidence above (0/3 vs 10/10, both ROCm versions). Upstream latent bug; CUDA's
   threadFenceReduction sample has the fence.
2. **Missing fault class: launch geometry derived from device properties overshoots on MI300X.**
   304 CUs x 2048 threads/CU gives 1216 blocks against an upstream bound of 1024 sized for NVIDIA
   parts (H100: 132 SMs). Evidence: `global_norm.cuh` assert on first run.
3. **Known gap 3, now measured: 64 KiB LDS opt-in cap, and a failed opt-in sets the last error.**
   Probe `repros/lds-optin/lds.hip`: `SharedMemPerBlockOptin` 65536; 48/64 KiB ok; 65..228 KiB
   `hipErrorInvalidValue` from `hipFuncSetAttribute`, sticky in `hipGetLastError`, launch fails.
   Same on 7.2.1 and 10.1.0. llm.c evidence above.
4. **Missing: stand-ins for APIs a ROCm release lacks must be version-gated, and validation must
   include the current ROCm release.** SKILL.md's validation bar names archs and OSes but not ROCm
   versions. Evidence: `test_gpt2fp32cu` builds on 7.2.1, fails on 10.1.0 (HIP 7.16 ships
   `cg::reduce`, `plus`, `less`, `greater` in `amd_hip_cooperative_groups.h:1329,1345` and
   `amd_hip_cooperative_groups_reduce.h:93`).
5. **Existing-port check is easy to perform and not act on.** SKILL.md says "grep the upstream's
   own docs" but not "stop and record a verdict before writing code", and the llm.c lesson lives
   only in the reference the agent never opened. Evidence: transcript command 1 printed README:206;
   no mention anywhere after.
6. Minor, not yet written up: `hipProfilerStart/Stop` return not-supported on ROCm 7 (`cudaCheck`
   around them aborts); `cublasSetMathMode(CUBLAS_TF32_TENSOR_OP_MATH)` has no hipBLAS equivalent.
7. Possible ambiguity, not acted on: the shim-header method (zero source edits) conflicts with the
   index line telling you to change every `0xffffffff` mask call site. The agent resolved it by
   wrapping the builtins in the shim. Worth a sentence once a second project shows the same tension.

---

# Validation run 2 (clean clone, same commit, updated skill)

| | |
|---|---|
| Skill | `moat-testing` @ `083f692` (8 commits: min/max, fence, grid, LDS, version gate + current-release validation, existing-port verdict, evals) |
| Env notes | same as run 1 except they now name ROCm 10.1.0 as the current release and its image (Matt's instruction). This **confounds** the ROCm-10.1 result: the skill now says to test the current release, and the notes say which one that is. |
| Transcript | `transcripts/llm.c-run2/` |
| Wall clock / turns / cost | 22 min 47 s, 90 turns, $5.00 |
| References read | `fault-classes.md` (first 230 lines), `strategy-a-cmake.md`, `assess-existing-support.md`, plus greps of the min/max entry (run 1: `strategy-a-cmake.md` only) |

| Gap / fault | Run 1 (old skill) | Run 2 (updated skill) | Counts? |
|---|---|---|---|
| 5 existing-port verdict | grep ran, hit ignored | verdict recorded first: URL, "community, not authoritative", "upstream links forks rather than merging, so a PR may not be accepted; contributing to the fork may be the realistic route". No PR or web search. | yes (partial: no extra searches) |
| 1 last-block fence | found at runtime (determinism fail) | **anticipated before first build** (step T3) | yes |
| 2 grid 1216 > 1024 | found at runtime (assert) | **anticipated before first build** | yes |
| (existing) fp32 `warpSize` OOB | found at runtime (memory fault) | anticipated before first build | side effect of reading fault-classes.md |
| 4 ROCm 10.1 | not tested; `test_gpt2fp32cu` fails to build on 10.1 | stand-ins gated (`__has_include` of HIP's header); built and tested on 7.2.1 and 10.1.0 | yes, but confounded by env notes |
| 3 LDS > 64 KiB | missed | **missed** (grepped `cudaFuncSetAttribute`, no action) | **no**: edit revised (`f6f8243`), re-validated in run 3 |
| new: `fused_residual_forward_kernel5` `if(idx > N) return;` off-by-one (upstream line 165; siblings use `>=`) | missed | found before building; fixed on AMD only, CUDA token stream left identical on purpose | existing OOB class |
| new: `wte_backward_kernel` barrier after early returns | missed | found, AMD-only fix | existing intra-wave barrier class |

Independent verification (mine, `tmp/llm.c-run2-score`):

| Check | ROCm 7.2.1 | ROCm 10.1.0 |
|---|---|---|
| `test_gpt2cu` BF16 x5 CI variants | 5/5 | 5/5 |
| `test_gpt2cu` FP32 x5 | 5/5 | 5/5 |
| `test_gpt2fp32cu` | ok | ok |
| LDS probe, `layernorm_forward` C=1920 FP32 | **abort `layernorm.cuh:460`** | **abort** |
| nvcc gate (sm_90, 5 targets, compile+link) | PASS, 0 errors | |

Diff: 10 tracked files, +144/-8, plus `hip_compat/`. All source fixes guarded by
`__HIP_PLATFORM_AMD__`; the agent reports nvcc `-E` output token-identical to upstream apart from
`__LINE__` values (not re-verified by me beyond the build). Tolerance changes again AMD-only
(BF16 `ln2w` 5e-2 -> 6e-2 for one element over by 0.8%; FP32 grads 5e-5, logits 2e-3, loss 2e-4).
Validation-bar gaps unchanged: no wave32, no Windows, no NVIDIA runtime, no multi-GPU.

---

# Validation run 3 (clean clone, same commit, LDS guidance revised)

| | |
|---|---|
| Skill | `moat-testing` @ `f6f8243` (run-2 skill + revised LDS index line + problem size as a validation axis) |
| Env notes | identical to run 2 |
| Transcript | `transcripts/llm.c-run3/` |
| Wall clock / turns / cost | 44 min 47 s, 115 turns, $7.86 (more runs: largest-size configs, SASS compare) |

| Gap | Run 2 | Run 3 |
|---|---|---|
| 3 LDS > 64 KiB | missed | **found and fixed**: ran `-e gpt3:c4096` BF16 (80 KiB request) and `-e d48` FP32 (64,000 B, just under); shim's `cudaFuncSetAttribute` clears the error on refusal so upstream's fallback kernel runs |
| 5 existing port | verdict, no PR search | verdict + PR search (found upstream PR #413 closed unmerged) |
| 1 fence / 2 grid / off-by-one | anticipated | anticipated; off-by-one fixed unconditionally (`idx >= N`), fence AMD-guarded |
| 4 ROCm 10.1 | tested | tested (CI-matrix script: 25/25 on 7.2.1 and 25/25 on 10.1.0, agent-reported) |

Independent verification (mine, `tmp/llm.c-run3-score`):

| Check | ROCm 7.2.1 | ROCm 10.1.0 |
|---|---|---|
| `test_gpt2cu` BF16 x5 / FP32 x5 / `test_gpt2fp32cu` | 11/11 | 11/11 |
| LDS probe `layernorm_forward` C=1920 FP32 (76,800 B) | **returns normally** (fallback) | **returns normally** |
| nvcc gate sm_90, 5 targets compile+link | PASS, 0 errors | |

Diff: 6 tracked files, +124/-12, plus `llmc/hip/` (12 files).

**Conclusion for llm.c:** all five evidenced gaps changed agent behaviour. Gaps 1, 2 and 5 were fixed by the first edit (run 2). Gap 4 was fixed in run 2, confounded by the env notes naming 10.1. Gap 3 was fixed only after a revision (run 3). Full eval set re-run after the revision: 11/11, no regression (`evals/after-iter1-rev/`).
