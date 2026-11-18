# cuda-samples (17-sample subset): blind port, run 1

- **Upstream:** NVIDIA/cuda-samples `0ec046d5` (2026-11-04, "Post v13.5").
- **Skill:** `f6f8243` (iteration-1 end state). **Env notes:** neutral (`prompts/env-notes.md`: both images
  listed, neither called current).
- **Request:** `prompts/request-cuda-samples.txt` (port the listed samples, pass their own checks, keep
  the CUDA build unchanged).
- **Subset:** basics (`vectorAdd`, `matrixMul`); texture pitch/layered/cubemap (`simplePitchLinearTexture`,
  `simpleLayeredTexture`, `simpleCubemapTexture`); warp/mask/cooperative groups (`simpleVoteIntrinsics`,
  `shfl_scan`, `reduction`, `reductionMultiBlockCG`, `binaryPartitionCG`); last-block fence
  (`threadFenceReduction`); `helper_math.h` (`dxtc`); cuRAND/cuFFT (`MC_EstimatePiP`,
  `convolutionFFT2D`); classify-not-port (`inlinePTX`, `simpleGL`, `nbody`).
- **Run:** 2026-11-17 14:21-15:07 (46 min), 131 turns, $10.19, exit 0. Transcript
  `transcripts/cuda-samples-run1/`; project `projects/cuda-samples/`; scoring copy
  `tmp/cuda-samples-score/`.

## Independent verification (my rebuild from a clean copy, GPU 7)

Built the agent's Dockerfile on each base image myself, then built, ran ctest and ran its stress sweep.

| | ROCm 7.2.1 | ROCm 10.1.0 |
|---|---|---|
| Build, 17 samples | clean, 0 errors | clean, 0 errors |
| ctest (17 samples + 3 added checks) | 20/20 | 20/20 |
| `hip/stress.sh` (block sizes, n, repeats) | 1347/1347 | 1347/1347 |

- **nvcc gate** (CUDA 13.0, compile only, sm_90, upstream per-sample CMake): 17/17 build, and the SASS of
  all 17 is identical to unmodified upstream (103k SASS lines compared).
  - The agent's `hip/cuda_nvcc_check.sh` does not create `$out/base` and `$out/port`. Without them it
    reports a false DIFF for every sample, because `cmp` compares two missing files. This is a harness
    robustness bug, not a port problem. The agent's own run had created the directories.
- **No checks weakened:** the source diff (10 files, +186/-28) touches no tolerance or exit path. All
  changes are under `__HIP_PLATFORM_AMD__`, with the CUDA code kept as the `#else` branch.
- **ctest validity:** samples decide pass/fail by exit status, as upstream does. The agent added three
  real checks:
  - a `binaryPartitionCG` result check against a host computation (upstream prints but never checks);
  - nbody GPU-vs-CPU in fp32 and fp64 (upstream's test arguments run only the CPU).
- **MI300X has no image support (verified):** `repros/image-support/img.hip` reports `imageSupport=0`,
  and `hipMallocArray` and `hipCreateTextureObject` (linear) return `hipErrorNotSupported`, on both ROCm
  versions. The agent's software texture path is therefore required on this GPU, not optional.
- **Upstream bugs claimed by the agent (verified by reading the source):**
  1. **nbody `-compare`:** the CPU reference uses softening² 0.00125 and damping 0.995
     (`bodysystemcpu_impl.h:48-49`), while the GPU gets the demo parameters' softening 0.1 and damping
     1.0 (`nbody.cpp:136`). So the comparison is only meaningful at small body counts.
  2. **threadFenceReduction:** `reduceBlock`'s 32-wide tree reads `sdata[tid+i]` past `blockDim.x` when a
     block has fewer than 32 threads, which is undefined behaviour. On AMD it fails every time at n=1.

## Behaviour against the skill

| Item | Observed | Credit |
|---|---|---|
| Strategy | shim-header method: a separate `hip/` CMake project, with shadow headers only on the HIP include path | skill (strategy-a reference read) |
| Existing-port check | done, but **at step 111 of 131, after the port**; verdict "none; rocm-examples/HIP-Examples are separate collections" | verdict plausible; the "before porting" ordering in c988011 was not followed |
| ROCm versions | 10.1 used from step 18 to diff the cooperative-groups API; stand-in selected by `__has_include` | neutral notes, so this cannot be credited to the env wording. Weak evidence for bc37f9a (n=1) |
| wave64: `simpleVoteIntrinsics`, `shfl_scan` (hardcoded 32 vs `warpSize`) | fixed | skill index (warp size) |
| Partial wavefront: 32-thread block in a `warpSize/2` shuffle | found, but at runtime | **gap → e2eb63c** |
| Fixed 32-wide LDS tree in a block narrower than 32 | found **at runtime by its own stress sweep** (16 failures before the fix) | **gap → 3a2979b** |
| Last-block fence | upstream already fences; the agent confirmed it and ran 50+ repeats | skill (8bc499a) |
| `helper_math.h` operator clash | fixed (HIP vector types already define the operators) | |
| CC 9.4 reported as "Blackwell" by `helper_cuda.h` | fixed (name by gfx target) | |
| Textures on gfx942 | discovered by its own probe at step 36; never opened `fault-classes.md` §Textures. The SKILL.md index only said texture limits are "arch-specific" | **gap → 06508d2** (index line) |
| Inline PTX | `%laneid` → AMDGCN `v_mbcnt` inline asm | |
| OpenGL samples | non-interactive modes run (`simpleGL -file`, nbody `-benchmark/-compare`); interactive modes stated as not runnable | |
| Validation bar | both ROCm versions; smallest and largest sizes; repeats; multi-arch compile (gfx90a, gfx1100) | good. wave32 compile only, not run |

## Skill gaps, discrimination test and decisions

| Gap | Evidence | Old skill on its eval (n=3) | New skill (n=3) | Decision |
|---|---|---|---|---|
| A block smaller than the wavefront: shuffles read lanes with no thread | `repros/wave64-partial/partial.hip`: 32-thread blocks 4096/4096 wrong, 64-thread blocks correct; 7.2.1 and 10.1.0 | flags the 32-thread case 3/3, but **3/3 say the sum may still come out right by luck** (disabled lanes read 0) | 0/3 luck claims; 3/3 say every block is wrong, citing the measurement | **kept: 0774273.** Eval tightened (luck claim is now unexpected) |
| A fixed-width LDS tree in a block narrower than the tree reads unwritten slots | same repro: 16-thread blocks 4096/4096 wrong after LDS is dirtied | 3/3 flag it and fix it | (same) | **held**, local branch `held/cuda-samples` (3a2979b) |
| gfx94x has no texture support, but the index didn't say so | `repros/image-support/img.hip` | 3/3 state no image support on gfx942 and plan a software path | (same) | **held** (06508d2) |

The detection-shaped evals still don't discriminate: the old skill finds all three once it is shown the
code. The one measurable difference is accuracy, where the old skill hedges that the sum might be
benign.

## Validation (step D)

### Blind re-port, run 2

- **Setup:** clean clone at `0ec046d5`, skill `0774273`, neutral notes, same request. 2026-11-17
  15:32-16:12 (40 min), 124 turns, $10.08. Transcript `transcripts/cuda-samples-run2/`, scoring copy
  `tmp/cuda-samples-run2-score/`.
- **My verification:**
  - ROCm 7.2.1 and 10.1.0 (images built from its Dockerfile): build clean; 17/17 samples pass with
    `test_args.json` arguments; 297/297 extended runs.
  - nvcc 13.0 per-sample build: 17/17 SASS identical to upstream.
  - The top-level CMake edits leave the top-level CUDA configure behaving as upstream does: both fail
    identically in this container, differing only by one warning line number.

| Item | Run 1 (f6f8243) | Run 2 (0774273) |
|---|---|---|
| Partial-wavefront shuffle in `reduction` | found at runtime | **anticipated**: lane-validity reduce written (step 64) before any sample was run (step 75), with a comment naming the half-wave64 case |
| Existing-port check | after the port (step 111) | **before starting**, verdict recorded |
| Texture reference | never opened; found by probing | read `fault-classes.md` §Textures at steps 6-7 (old text was enough, which supports holding 06508d2) |
| threadFenceReduction tiny-block LDS read | found at runtime by stress sweep | found at runtime by extended runs (step 83) |
| Last-block fence | confirmed upstream fence | added an acquire fence in the last-block branch as well |
| Build shape | separate `hip/` CMake project | `CUDA_SAMPLES_USE_HIP` option in the upstream CMake (more invasive, but the CUDA output is unchanged) |
| Known limits stated | yes | yes, including reduction kernels 4-6 with blocks under 32 threads (not exercised by default sizes, left unfixed) |

Reading: the kept edit changed behaviour in the direction intended (n=1 each; per the control-run
lesson, this is suggestive, not proof). The existing-port ordering also improved, without any edit
since c988011.

### Full eval re-run (0774273)

- **Triggers:** all 9 should-trigger evals invoked the skill; the 3 negatives did not.
- **Graded evals:** keyword checks are identical to the previous run, and spot-reads (wave64,
  min/max, torch plan, warp-reduce) are on target. **No regressions.**
- **Known quirk:** the `review-kernel-for-wave64` agent again wrote to a mistyped `-work` path.

## Not testable here

wave32/RDNA runtime, NVIDIA runtime, multi-GPU, the interactive OpenGL modes, and the hardware texture
path on AMD GPUs that do have image support.
