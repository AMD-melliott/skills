# pytorch3d: blind port, run 1

- **Upstream:** facebookresearch/pytorch3d `ddfc551` (2026-11-17). **Skill:** `72a85eb`. **Env notes:** neutral.
  **Request:** generic.
- **Run:** 2026-11-17 18:53-19:33 (40 min), 10 turns (most of its work ran through Monitor), 95 Bash
  calls, $5.16, exit 0. Transcript `transcripts/pytorch3d-run1/`; project `projects/pytorch3d/`;
  scoring copy `tmp/p3d-score/`.

## What the agent did

- **Existing AMD port found and used correctly.** Upstream already contains Jeff Daily's (AMD) HIP port,
  `b73d735` "Port pytorch3d (#2039)", 2026-06-01, which is torch-hipify based. It was validated on gfx90a
  and gfx1100 but not on gfx942, and 36 commits have landed since. The agent validated that port on the
  MI300X and fixed what that turned up, rather than re-porting. This is the skill's "authoritative AMD
  port → validate and improve" path.
- **Changes** (6 files, +76/-58):
  - `setup.py`: `-std=c++20` for torch ≥ 2.14. Upstream otherwise fails on torch 2.14 under both CUDA
    and ROCm.
  - `warp_reduce.cuh`: a wavefront-scope fence in place of the ROCm branch's missing `__syncwarp()`.
  - 4 test modules: guard their `MeshRasterizerOpenGL` import, so that `PYTORCH3D_NO_TEST_OPENGL=1`
    stops losing all the other tests in those files.

## Independent verification

| Environment | Build | `tests/` (OpenGL off) | pulsar (`FB_TEST=1`) | agent's large-size checks |
|---|---|---|---|---|
| torch 2.14.1+rocm7.2 (agent's image) | clean | 919 passed / 8 failed / 61 skipped (= agent's claim) | 10/10 | 15/15 |
| **`rocm/pytorch:rocm10.1.0_ubuntu24.04_py3.12_pytorch_release_2.14.0`** (HIP 7.16; never run by the agent) | clean | 918 / **9** / 61 | 10/10 | 15/15 |

- **The 8 common failures:** environment problems, exactly as the agent described (pandas 3 ×3, numpy 2
  glTF ×4, pulsar's imageio debug write ×1).
- **The extra failure on 10.1** is `test_simple_sphere_elevated_camera`, max diff 0.498, which is
  deterministic.
  - My per-case diagnosis (`tmp/p3d-score/_diag.py`) shows exactly 1 silhouette pixel differing from
    the reference, and only for the two orthographic cameras.
  - **The CPU render differs from the reference in the same pixel**, and the GPU and CPU renders agree.
  - So it is a torch-build numerical difference on an edge pixel, not a HIP, GPU or port defect.
  - On 7.2 the same diagnosis gives 0 pixels for every case.
- **CUDA gate** (my rebuild in the agent's cu130 images, `FORCE_CUDA=1`, sm_80+90):
  - torch 2.13.0+cu130: upstream and port both build; SASS identical for all 31 objects with device code
    (67 objects in total).
  - torch 2.14.1+cu130: upstream **fails** ("C++20 or later compatible compiler is required to use
    ATen"); the port builds.
  - (My first two gate attempts were wrong: one copy dropped `__init__.py` through an over-broad rsync
    exclude, and one comparison did not map the absolute object paths. Both are fixed; the numbers above
    are from the corrected run.)

## Behaviour against the skill

| Item | Observed |
|---|---|
| Existing-port check | **Excellent**: found the merged AMD port, recorded the verdict, validated and improved it |
| Strategy | B (torch hipify), with sources kept in CUDA spelling |
| Wave64 review | pulsar ballot/popc, hipCUB BlockReduce at block sizes 2-1024, `iou_box3d` FMA: reviewed, correct |
| Largest sizes | 200k points, 2048² rasterization, KNN 20k×30k: done |
| CUDA gate | done, SASS-level |
| **ROCm versions** | **only ROCm 7.x**: torch 2.13+rocm7.1 and 2.14+rocm7.2 wheels on a 7.2.1 base. It never considered 10.1. Under the same neutral notes, both Strategy A projects (cuda-samples, cuCollections) did test on 10.1 |

## Gap tested and held

- **Edit** `8179321` (local `held/pytorch3d`):
  - SKILL.md validation bar: "for a torch extension the ROCm under test is the one the torch build
    targets".
  - `strategy-b-torch.md`: how to get a torch for the current ROCm.
  - Eval `torch-extension-validation-matrix`.
- **Discrimination (n=3):** the old skill already plans a ROCm 10.1 leg with a 10.1-built torch, 3/3
  (`tv-old-*`). The new skill does the same, 3/3. **Not discriminating, so held.**
- **Reading:** the skill knows this when asked to plan a validation matrix, but the blind port never
  stopped to plan one. Its validation grew out of whatever torch wheels matched the base image. This is
  the same "process, not knowledge" pattern as the iteration-1 method finding. An eval cannot show it;
  only blind ports do.

## Not testable here

wave32/RDNA, the NVIDIA runtime, multi-GPU tests, and the OpenGL rasterizer (pycuda/CUDA-GL interop; no
graphics pipeline on CDNA).
