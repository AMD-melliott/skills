# Test environment: moat-cuda-to-rocm skill testing

Recorded 2026-11-17 on host `SMC-SC-DC19-06` (tme-server).

## Host

| Item | Value |
|---|---|
| OS / kernel | Ubuntu 24.04.5 LTS, 6.14.0-37-generic |
| CPU / RAM | 2x AMD EPYC 9374F (128 threads), 2.2 TiB |
| amdgpu driver | 6.19.14.31400000 |
| ROCm (host) | 7.2.1 (`/opt/rocm/.info/version`); AMDSMI 26.2.2 |
| GPUs | 8x AMD Instinct MI300X, `gfx942:sramecc+:xnack-`, wave64, 64 KiB LDS per block (`sharedMemPerBlock` = 65536) |
| Power cap | 750 W per GPU (max) |
| Work disk | `/data` -> `/mnt/data` (md0, 14 TB, ~1.3 TB free at start). NFS home not used. |
| Docker | 29.1.3, root dir on `/mnt/data`; podman also present |
| Shared use | RKE2 cluster running EAI Suite; vLLM/Triton workloads on other GPUs |

## GPU selection (single GPU only)

Usage at start (`amd-smi process`, `amd-smi metric -m`):

| amd-smi GPU | HIP index | BDF | VRAM used | Owner |
|---|---|---|---|---|
| 0 | 0 | 0000:05:00.0 | 187 GB | vLLM (root) |
| 1 | 1 | 0000:26:00.0 | 181 GB | vLLM worker |
| 2 | 2 | 0000:46:00.0 | 177 GB | vLLM worker |
| 3 | 3 | 0000:65:00.0 | 1.3 GB | tritonserver |
| 4 | 4 | 0000:85:00.0 | 183 GB | vLLM (gemma) |
| 5 | 5 | 0000:a6:00.0 | 179 GB | vLLM |
| 6 | 6 | 0000:c6:00.0 | 0.3 GB | idle |
| **7** | **7** | **0000:e5:00.0** | 0.3 GB | **idle -> used for testing** |

HIP and amd-smi index order were verified to agree on this host by printing
`hipDeviceGetPCIBusId` for each `HIP_VISIBLE_DEVICES=<i>` (`tools/pcimap.hip`).

**Isolation:** GPU containers get `--device=/dev/kfd --device=/dev/dri/renderD184` only
(renderD184 = `pci-0000:e5:00.0-render`), so they can physically see one GPU, plus
`HIP_VISIBLE_DEVICES=0` inside. Verified: `pcimap` in such a container lists only e5:00.0.
Re-check `amd-smi process` before each run; if GPU 7 is taken, stop.

No multi-GPU runs. This host has tripped PDU breakers under full multi-GPU load.

## Toolchain containers

| Purpose | Image | Notes |
|---|---|---|
| ROCm build/run | `rocm/dev-ubuntu-24.04:7.2.1-complete` | matches host ROCm 7.2.1; HIP 7.2.53211, AMD clang 22.0.0git; Python 3.12.3; **no cmake** (pip/apt per project) |
| CUDA no-regression gate | `nvidia/cuda:12.8.1-devel-ubuntu24.04` | nvcc 12.8.93. **Works**: compile + link of a test `.cu` at `-arch=sm_80` succeeded. Compile/link only; no NVIDIA GPU, nothing can run. |
| ROCm current release | `rocm/dev-ubuntu-24.04:10.1.0-full` | ROCm 10.1.0 (`amdrocm-core-dev10.1-*` 10.1.0-3), HIP 7.16.26385, AMD clang 24.0.0git. **Runs on GPU 7 with the host's amdgpu 6.19.14 driver** (verified with `pcimap`). Image has no `render` group name, so `rocm-run` passes numeric GIDs (44 video, 993 render). No `/opt/rocm/.info/version` file. |
| ROCm 10.2 | not yet published (Docker Hub tags checked 2026-11-17) | re-check each iteration |
| PyTorch projects | `rocm/pytorch` (to be matched to 7.2.x when needed) | local `rocm/pytorch:latest` and a rocm10.0 image exist; pick per project |

## ROCm version policy

Per Matt (2026-11-17): ROCm 10.1 is the current release (10.2 pending); test against the recent
release at least equally with 7.x. Every port is scored by building and running its tests on
**both** 7.2.1 and 10.1.0 in containers on GPU 7. The host stays on 7.2.1 (no ROCm changes).

## Host trap found during inventory

Host `hipcc` (ROCm 7.2.1) picks up **Ubuntu's `libamdhip64-dev` headers in `/usr/include/hip`
(HIP 5.7)** ahead of `/opt/rocm/include`, so a trivial HIP program fails on the host with
`use of undeclared identifier '__AMDGCN_WAVEFRONT_SIZE'` from
`/usr/include/hip/amd_detail/amd_warp_functions.h`. Not changed (no system edits allowed).
All builds therefore run in containers. Worth knowing if any agent tries a host build.

## Validation-bar gaps on this host (record in every result)

- **Wave32 / RDNA: not available.** Only gfx942 (wave64). The skill's bar requires one RDNA
  GPU; no result here can claim wave32 coverage.
- **Windows: not available.**
- **NVIDIA runtime: not available.** The nvcc gate is compile+link only.
- **Multi-GPU (RCCL collectives): not exercised** by policy (single GPU).

## Agent harness

- Claude Code 2.1.326, headless `claude -p` per blind agent, launched in the project dir
  (no vault CLAUDE.md, no project memory).
- `--settings blind-settings.json` disables every installed plugin (so no superpowers or other
  plugin guidance or hooks); `--strict-mcp-config` drops MCP servers. Verified the agent's skill
  list is the built-ins plus `git-status-review`, `hf-cli`, `moat-cuda-to-rocm`.
- Skill installed by symlink `~/.claude/skills/moat-cuda-to-rocm ->
  /data/melliott/moat-testing/skills/skills/moat-cuda-to-rocm` (fork, branch `moat-testing`).
- `--dangerously-skip-permissions` for sub-agents was refused by the auto-mode safety
  classifier; evals run with an explicit tool allowlist instead.

## Skill provenance

`skills/moat-cuda-to-rocm/.federated.json`: federated from `AMD-Ecosystem/moat`
(`.claude/skills/cuda-to-rocm`, commit 030f06f4, imported 2026-11-12). Changes proposed to
amd/skills may need to go to that source repo instead.
