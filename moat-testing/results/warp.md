# NVIDIA/warp: blind port, run 1

- **Upstream:** NVIDIA/warp `2d5493bb0` (2026-11-17). **Skill:** `72a85eb`. **Env notes:** neutral.
  **Request:** generic.
- **Run:** 2026-11-17 20:11-23:15 (**3 h 4 min**), 400 turns, **$67.09**, exit 0. This is by far the largest
  run; the next largest was $18.80. Transcript `transcripts/warp-run1/`; project `projects/warp/` (local
  branch `melliott/rocm-port`, 24 commits over `main`, **not pushed**: the only remote operation was
  `git fetch amd`).
- **Scoring copies:** `tmp/warp-score/` (clean clone of the branch) and `tmp/warp-cuda-gate/`.

## What the agent did

- **Existing-port check, done correctly:**
  - Upstream closed AMD's HIP PRs (#1770, #1932); the maintainers' position (#1960) is that HIP lives
    in a fork.
  - The agent found **AMD-Ecosystem/warp** (AMD-official, maintained) and judged it authoritative.
  - It merged the fork's `amd-integeration-dev` (391 commits behind) into current `main` and finished the
    port for everything upstream had added since.
  - It kept CUDA unchanged where the fork had changed CUDA behaviour (BVH builder, cuBQL revision, an
    ABI change, a CPU-path regression).
- **Its own fixes on top of the fork** include:
  - tile lane-width hooks for wave64/wave32;
  - a bf16 `atomic_add` that took a non-atomic path in HIP device code;
  - deterministic-mode divergence reporting;
  - HIP context API aliasing `cuda:0`;
  - `-ffp-contract=on` for hipRTC;
  - a texture capability flag;
  - clearing HIP's last error after handled `cu*` failures, which hipCUB otherwise resurfaces;
  - an acquire `__threadfence()` in BVH construction (MI300X per-XCD L2), added while reviewing the
    fork's BVH rewrite after testing had started (step 119; the first suite run was at step 42).

## Independent verification

| Check | Result |
|---|---|
| **ROCm 10.1.0**, clean clone, **documented command** (`uv run build_lib.py --hip-arch=gfx942 ...`), Warp's runner `-j 24` | **9441 tests, OK, 475 skipped**, which matches the agent |
| **ROCm 7.2.1**, clean clone, **documented command** | **BUILD FAILS**: `tile.h:80: fatal error: hip/hip_runtime.h: No such file or directory` (see below) |
| ROCm 7.2.1 with `ROCM_PATH=/opt/rocm` and `/opt/rocm/bin` first on PATH (what the agent's `.port-tools/rr` wrapper sets), clean rebuild | **9441 tests, OK, 475 skipped**, which matches the agent. The port's code is fine on 7.2.1; only the documented build command fails |
| CUDA gate: nvcc 12.8 with libmathdx; upstream `2d5493bb0` and the port both build | `warp.so` SASS **identical**: 13,364,628 lines, once path-derived symbol hashes are normalised (anonymous-namespace `_GLOBAL__N__<hash>` and `<file>_cu_<hash>_<n>` differ only because the two checkouts sit at different paths) |
| ROCm 7.2.1 SLP miscompile (agent's claim) | **Confirmed**, see `repros/rocm721-slp-qr/README.md`: -O2/-O3 wrong by 15.95; -O0/-O1, `-fno-slp-vectorize` and ROCm 10.1 correct. **Flagged, not filed** |
| `hiprtcVersion()` reports 9.0 on both releases (agent's claim) | **Confirmed** (`repros/hiprtc-version/`): 9.0 on both, while `hipRuntimeGetVersion()` gives 70253211 vs 71626385 |
| Intermittent multi-process D2D copy corruption on 7.2.1 under load (agent's observation: one XCD's worth of 256-element blocks unwritten) | **Not reproduced or attempted.** It needs 24 concurrent processes on the GPU. Still the agent's unverified observation |

### Port defect: ROCm auto-detection breaks on a stock ROCm 7.2.1 image

- `warp/_src/build_dll.py` `find_rocm_sdk()` returns `dirname(dirname(os.path.abspath(shutil.which("hipcc"))))`.
- In `rocm/dev-ubuntu-24.04:7.2.1-complete`, `hipcc` is `/usr/bin/hipcc`, a symlink through
  `/etc/alternatives` to `/opt/rocm-7.2.1/bin/hipcc`. `abspath` does not resolve symlinks, so the ROCm
  root comes out as `/usr` and g++ gets `-I/usr/include` (no HIP headers).
- In the 10.1 image the same logic happens to find `/opt/rocm`.
- The agent never saw this, because every one of its builds went through `.port-tools/rr`, which
  exports `ROCM_PATH=/opt/rocm` and puts `/opt/rocm/bin` first on PATH. Its PORT_SUMMARY documents the
  plain command, which fails on 7.2.1.
- Fix: `os.path.realpath`, or prefer `hipconfig --rocmpath`.
- **This is the second iteration in a row where validation passed only inside the agent's own
  environment.** cuCollections had gitignored patch files; warp has a wrapper that exports env vars.
  A clean-clone, documented-command rebuild catches both.

## Skill gaps → commits

| Gap | Discrimination (n=3) | Decision |
|---|---|---|
| ROCm 7.2.1 SLP-vectorizer miscompile; gate the workaround on `hipRuntimeGetVersion()` (not `hiprtcVersion()`) | Old skill: proposes the flag bisect including `-fno-slp-vectorize` and suspects codegen, but 0/3 mention that the bug is known in 7.2.1 and fixed in 10.1, and 0/3 give the correct version gate (one suggests logging `hiprtcVersion`). New skill: 3/3 name the known issue, ROCm 10.1 and `hipRuntimeGetVersion` | **kept: c7e73fd.** Eval tightened (no newer-ROCm check, or gating on `hiprtcVersion`, is unexpected) |
| Validate from a clean clone with the documented command in a fresh environment | (process; an eval cannot show it) | **Not edited.** Recommended to Matt along with held `f698bb2`: two independent blind ports hid real defects this way |

- **Full eval re-run (c7e73fd):** 11/11 should-trigger evals invoked the skill, 3/3 negatives did not;
  graded keyword checks unchanged. **No regressions.**
- **Step D blind re-port: not run.** A warp run costs about 3 h and $67, and run 1 already found the
  miscompile and gated it correctly, so a re-port cannot show the edit changing behaviour. Matt's call
  if he wants one.

## Not testable here

wave32/RDNA (the tile wave32 branch was never compiled for RDNA), gfx90a (which has texture hardware, so
the HIP texture path has not run on any GPU), Windows, the NVIDIA runtime (CPU-device tests against the
CUDA build were run by the agent), multi-GPU, and graph capture (disabled on HIP by the fork's design).
