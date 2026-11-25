# Current-ROCm evidence for the cuda-to-rocm PRs (2026-11-24)

**Scope.** Every factual claim in PRs 1, 3, 4 and 5 was re-run on ROCm 7.14.1, 10.1.0 and 10.2.0, the current release. Per Matt, nothing older than 7.14.1 was tested.

**Setup.**
- All runs were sequential on MI300X GPU 7 (gfx942), using stock `rocm/dev-ubuntu-24.04:<ver>-full` images and `rocm/pytorch:rocm10.2.0_ubuntu24.04_py3.12_pytorch_release_2.15.0`.
- The host is amdgpu 6.19.14 with ROCm 7.2.1 userspace; all ROCm userspace under test ran in containers.
- Each folder holds the script that produced its logs.

**Image quirk on 7.14.1.** The 7.14.1 image does not put `/opt/rocm/core-7.14/lib` on the loader path. Binaries built there fail with `libamdhip64.so.7: cannot open shared object file` until `LD_LIBRARY_PATH` points at it. Every 7.14.1 run here sets it, and the logs show it.

## PR 1: fault classes (`pr1/`, `pr1-llmc/`)

| Claim | 7.14.1 | 10.1.0 | 10.2.0 |
|---|---|---|---|
| Shuffle sum in a 32-thread block on wave64 is wrong; a 64-thread block is right | 4096/4096 wrong; 0/4096 | same | same |
| 16-thread block over a 32-wide shared-memory tree reads unwritten LDS | 4094/4096 wrong | 4096/4096 | 4096/4096 |
| LDS opt-in: 64 KiB is OK; from 65 KiB `hipFuncSetAttribute` gives `hipErrorInvalidValue`, the next `hipGetLastError()` returns it, and the launch fails | yes; `SharedMemPerBlockOptin` = 65536 | same | same |
| llm.c `layernorm_forward` (FP32) through the port: C=1638 runs; C=1639 and C=1920 abort at `layernorm.cuh:453 invalid argument` | yes | yes | yes |
| llm.c without the `__threadfence()` in `layernorm_backward_kernel10`: `Nondeterminism! Loss mismatch at step 1` | 3/3 runs | 3/3 | 3/3 |
| llm.c with the fence: 10 test configurations (BF16/FP32 × default, `-r 0`, `-r 2`, `-w 0`, `-b 32`) pass | 10/10 | 10/10 | 10/10 |
| Grid from `multiProcessorCount` (304 × 2048 / 512 = 1216 blocks) trips llm.c's `assert(gx * gy < 1024)` | assert fires | fires | fires |
| `hipDeviceAttributeImageSupport` = 0; `hipMallocArray` and `hipCreateTextureObject` (linear) give `hipErrorNotSupported` | yes | yes | yes |
| Host read of a `__device__ constexpr` table through a pointer gets the zeroed host shadow (`0 9.2e18 0 0`) | yes | yes | yes |
| Host `min`/`max` on non-int arguments truncate: `min(0.25f,3.7f)=0`, `max(0.5,0.75)=0`, `max(3000000000u,1u)=1` | yes | yes | yes |
| `__HIP_DEFINE_EXTENDED_HOST_MIN_MAX__` defaults to 0; with it set to 1, all four are right; the `static_assert` guard fails by default and passes with the define | yes | yes | yes |
| libhipcxx `amd-develop` head (`832dc407f`, unchanged since 2026-11-17): `atomic_ref` strong CAS fails spuriously on 1- and 2-byte types; 4-byte is clean | 75% / 50% / 0 | same | same |
| The same with the cuco port's patch | 0 / 0 / 0 | same | same |
| The `hipccl` copy ROCm bundles has the same CAS defect | not bundled | 75% / 50% | **75% / 50%** (still shipping) |
| `atomic_ref` on an under-aligned 8-byte struct fails to build (`unsupported cmpxchg: instruction alignment 4`); the cuco patch fixes it (`{1,2}`) | yes (compile error) | yes (link error; bundled hipccl too) | same as 10.1 |
| `hiprtcVersion()` is 9.0 while `hipRuntimeGetVersion()` changes | 9.0 / 71460850 | 9.0 / 71626385 | 9.0 / 71726434 |

## PR 3: ROCm release and problem size (`pr3-llmc/`, `pr3-p3d/`, `pr1-llmc/`)

| Claim | 7.14.1 | 10.1.0 | 10.2.0 |
|---|---|---|---|
| An unconditional `cg::plus`/`less`/`greater` shim fails: `redefinition of 'plus'` (`test_gpt2fp32cu`) | fails | fails | fails |
| The same shim gated on `__has_include(<hip/cooperative_groups/hip_reduce.h>)` builds, and `test_gpt2cu` and `test_gpt2fp32cu` pass; the LDS fallback runs at C=1920 | yes | yes | yes |
| One container per release on the same GPU with no host driver change | ran on a host with amdgpu 6.19.14 and ROCm 7.2.1 | same | same |
| pytorch3d port on AMD's torch for the current ROCm (`torch 2.15.0+rocm10.2.0`, HIP 7.17): builds; `tests/` 921 passed, 6 failed; pulsar 10/10; large-size checks pass | | | yes |

The 6 pytorch3d failures on 10.2.0:
- 4 glTF tests, from numpy 2.
- 1 pulsar test that needs `FB_TEST`.
- `test_simple_sphere_elevated_camera`. `diag-r102.log` shows it is 1 silhouette pixel for the orthographic cameras only. The CPU render differs from the reference in the same pixel, and the GPU and CPU renders agree. That matches the 10.1.0 finding.

## PR 4 and PR 5: fresh-clone rebuilds of the delivered work (`round2/v4/*-{7.14.1,10.2.0}*.log`, `pr5-cuco-ignore/`)

Every rebuild is a fresh clone of what the run committed, run with only its documented commands on a stock image. "diag" adds the one flag the documentation omits.

| Deliverable | 7.14.1 | 10.2.0 |
|---|---|---|
| hipCollections contribution cuco-C-1 | 694/694 | 694/694 |
| cuco-C-2, documented commands | configure fails fetching nvbench (`release/26.10` does not exist) | same |
| cuco-C-2 diag (`-DBUILD_BENCHMARKS=OFF`) | 694/694 | 694/694 |
| cuco-B4r-1 / -2, documented commands | configure fails (nvbench) | same |
| cuco-B4r-1 / -2 diag | 700/700, 689/689 | 700/700, 689/689 |
| rccl-tests contributions nccl-B4r-1 / -2 | **not testable**: unmodified rccl-tests at the same rocm-systems base (`45dfe66`) fails to compile against 7.14.1's RCCL (`NCCL_GIN_TYPE_ROCSHMEM_GDA` undeclared; base commit `4791efc5e7`, 2026-10-14) | **12/12 binaries pass, all dtypes including fp8**. The fp8 aborts seen on 7.2.1 and 10.1.0, which unmodified rccl-tests also had, are gone |
| llm.c contributions llmc-C1 / llmc-C2 | pass | pass |
| llm.c port llmc-A2, documented `make` | `./test_gpt2hip` aborts: "MPI support is disabled" (images ship `rccl.h`, no MPI) | same |
| llmc-A2 diag (`NO_MULTI_GPU=1`) | pass | pass |
| pytorch3d contributions p3d-C1 / p3d-C2 | 926 passed, 1 failed (pulsar without `FB_TEST`) / 910 passed, 7 failed (glTF, SQL) | same counts |
| cuCollections round-1 port, configured from what a commit would capture (`git ls-files -co --exclude-standard`) | `Couldn't find patch file .../libhipcxx_atomic_alignment.diff`; upstream `.gitignore:55` `*.diff` hides both patches | same |
| The same plus the two ignored patch files | configures; both patches apply | same |

The cuCollections ignore test needs CMake 4: upstream pulls rapids-cmake `main`, which now requires it. In the 10.2.0 leg, the `committed` directory was re-used from a first attempt that had pinned CMake below 4; its contents are the same overlay.

## Claims that do NOT hold on current ROCm (drop from the PRs)

- **PR 5, Warp:** the port's ROCm auto-detection resolved `/usr` on the 7.2.1 image only. From 7.14.1 on, `hipcc` is `/opt/rocm/bin/hipcc`, so the same logic finds `/opt/rocm`, which was checked in each image. This is a 7.2-only example.
- **PR 2, SLP miscompile:** 7.2-series only (`repros/rocm721-slp-qr/README.md`). Already dropped.

## Candidate AMD defects still present on 10.2.0 (untriaged beyond the repro; not filed)

- **libhipcxx strong CAS acting as weak for 1- and 2-byte types.** It is in the `amd-develop` head and in the `hipccl` that ROCm 10.2.0 bundles. Triage: the compiler builtins are correct (strong 0%, weak 75%/50%), so the defect is in the wrapper. Repro: `repros/libhipcxx-cas/`.
- **libhipcxx `atomic_ref` on an under-aligned 8-byte type fails to build, including the bundled `hipccl`.** This is a portability gap against libcu++, not a miscompile.
