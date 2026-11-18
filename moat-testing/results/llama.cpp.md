# llama.cpp (negative control): blind run 1

- **Upstream:** ggml-org/llama.cpp `4577932fa` (2026-11-18). **Skill:** `c7e73fd`. **Env notes:** neutral.
  **Request:** generic ("Port this CUDA project to ROCm/HIP ...").
- **Run:** 2026-11-18 00:00-00:39 (39 min), $3.99, exit 0. Transcript `transcripts/llama.cpp-run1/`;
  project `projects/llama.cpp/` (uncommitted, 2 files, +7/-12); scoring trees `tmp/llama-score/`.

## Negative-control verdict: passed

- **Did not re-port.** The agent recognised that the upstream HIP backend (`-DGGML_HIP=ON`, `ggml-hip/`,
  `vendors/hip.h`) is authoritative and maintained.
- **Validated it** on MI300X, on both ROCm releases, with `test-backend-ops` (every op on ROCm0 vs CPU),
  ctest, an end-to-end perplexity comparison (GPU 14.2516 vs CPU 14.2611) and a CUDA compile gate.
- **Fixed two real upstream bugs** it found that way. It respected the repo's AGENTS.md rule that a human
  must write and submit PRs: nothing was committed, pushed or opened.

## The two fixes (both verified)

1. **NVFP4 scales decoded at half value on CDNA3** (`common.cuh`).
   - A `GGML_USE_HIP && CDNA3` branch (upstream #21040, `7ca0c9cca`) reinterprets the OCP E4M3 scale byte
     as `__hip_fp8_e4m3_fnuz` and then divides by 2.
   - FNUZ's exponent bias is 8, not 7, so the reinterpretation already halves the value, and every NVFP4
     scale ends up at 0.5x.
   - The agent proved it with a 256-byte GPU probe; the fix removes the branch so CDNA3 uses the generic
     decode.
   - This is an upstream llama.cpp bug in AMD-specific code, not an AMD platform bug.
2. **Cooperative softmax drops partials on GPUs with more than 256 CUs** (`softmax.cu`).
   - The grid is one block per SM/CU; one 256-thread block reduces the partials, and the assert guarding
     that is compiled out in Release.
   - MI300X's 304 CUs means blocks 256-303 are lost. The fix caps the grid at `min(nsm, 256)`.
   - This is a no-op on every NVIDIA GPU (all have fewer than 256 SMs).
   - It is **the same "launch geometry from device properties" class as llm.c's `global_norm` assert**
     (skill commit bdeabb0). It was found here by a test failure, not anticipated.

## Independent verification (my builds, clean clones at `4577932fa`, GPU 7)

| Tree | ROCm | `test-backend-ops test -b ROCm0` |
|---|---|---|
| upstream (unchanged) | 7.2.1 | 20,143 / 20,504 passed: **361 failures** (358 NVFP4 across MUL/MUL_MAT/MUL_MAT_ID/ADD, 3 SOFT_MAX). The agent reported 362; the difference does not change the result |
| port (agent's diff applied) | 7.2.1 | **20,504 / 20,504** |
| port | 10.1.0 | **20,504 / 20,504** |

- **CUDA gate:** nvcc 12.8, sm_90, `ggml-cuda` target from the port tree: 162/162 steps, 0 errors.
- **Not re-run by me:** ctest (the agent's 72/72 after fixing Python and git-lfs in its image), the
  perplexity end-to-end, and the agent's ue4m3 probe.

## Skill observations

- **Existing-port handling:** correct, just as for pytorch3d and warp. Across the run order, only
  cuCollections (the hipCollections duplicate) went against the skill.
- **Candidate fault class, not edited:** reading OCP E4M3 bits as FNUZ halves the value.
  - The skill notes only that gfx942's native FP8 is FNUZ.
  - Every review-shaped eval so far has been caught by the old skill once it sees the code, so an
    eval here would likely not discriminate.
- **Grid-from-device-props:** found by a test failure, not by review before running. That is the same
  outcome as cuda-samples run 1 and cuCollections run 1 for their gaps.
- **Hygiene:** the agent's containers ran as root (`rocm-run`'s default) and left root-owned
  `build-hip*/` and `models/ggml-vocabs/` in the project. Harmless here, but worth a line in the env
  notes next time.
