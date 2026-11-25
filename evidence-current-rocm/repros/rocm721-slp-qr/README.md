# ROCm 7.2.1 device compiler miscompiles a 10x10 float Householder QR at -O2/-O3 (SLP vectorizer)

**Status: flagged for Matt. Not filed. Already fixed in ROCm 10.1.0's compiler.** Found by the NVIDIA/warp
blind port (2026-11-17; Warp's `block_jacobi_direct` preconditioner inverse was wrong by up to 7e-3).
Reproduced here independently.

## Repro

`qr_repro.hip` is the agent's standalone reproducer: Warp's generated `_qr_decomposition_0` for a
`mat_t<10,10,float>`. It runs the same function on the host and on the device for 4 well-conditioned SPD
matrices (`C·Cᵀ + 10·I`) and prints the largest difference between the two. It needs the port's
`warp/native` headers, copied into `./warp/native` from the port branch.

```bash
rocm-run [--image rocm/dev-ubuntu-24.04:10.1.0-full] bash -lc \
  'hipcc -std=c++17 --offload-arch=gfx942 -O2 -I warp/native -w -o /tmp/qr qr_repro.hip && /tmp/qr'
```

| Flags (gfx942) | ROCm 7.2.1 (HIP 7.2.53211) | ROCm 10.1.0 (HIP 7.16.26385) |
|---|---|---|
| -O0 | 3.8e-06 | 0 |
| -O1 | 3.8e-06 | 3.8e-06 |
| **-O2** | **15.95** | 3.8e-06 |
| **-O3** | **15.95** | 3.8e-06 |
| -O3 -fno-slp-vectorize | 3.8e-06 | 3.8e-06 |
| -O3, host at -O0 (`-Xarch_host -O0`) | **15.95** | 3.8e-06 |

## Triage

- **The device side is wrong, not the host reference.** Keeping the host at -O0 does not change the 7.2.1
  result.
- **This is not floating-point reassociation.** Q is orthonormal (|entries| ≤ 1), yet the error is 16,
  far beyond rounding. The same source is correct at -O0/-O1, with `-fno-slp-vectorize`, and with the
  10.1 compiler at every level.
- **This is not an input dtype problem** (the skill's dtype check): inputs are float32 SPD matrices with
  a diagonal of about 10+.
- **Not done:** reducing the repro below Warp's generated code (about 100 lines of straight-line matrix
  code), and bisecting the LLVM pass beyond "disabling SLP fixes it". A UB-based miscompile can't be
  fully excluded without a sanitizer pass, but the -O level and compiler-version pattern strongly
  suggests the compiler.

## Workaround in the port

Warp passes `-fno-slp-vectorize` to hipRTC and hipcc only when the HIP runtime is older than 7.16. Gating
is by `hipRuntimeGetVersion()`, because `hiprtcVersion()` reports 9.0 on both ROCm versions.

## Worth knowing for anyone filing

The defect is in a shipping release (7.2.1) and gone in the current one (10.1.0). Filing value is
mainly for users pinned to 7.2.x, or a 7.2.x point release.

## Version sweep (2026-11-24)

The same reproducer, same flags, on GPU 7, with stock `rocm/dev-ubuntu-24.04` images. 7.14.1 and 10.0.0 needed `LD_LIBRARY_PATH=/opt/rocm/core-<ver>/lib` to run. Log: `sweep.log`.

| ROCm (HIP) | Image pushed | -O1 | -O2 | -O3 | -O3 -fno-slp-vectorize |
|---|---|---|---|---|---|
| 7.2.1 (7.2.53211) | 2026-03 | 3.8e-6 | **15.95** | **15.95** | 3.8e-6 |
| 7.2.2 | 2026-04 | 3.8e-6 | **15.95** | **15.95** | 3.8e-6 |
| 7.2.4 (last 7.2) | 2026-05 | 3.8e-6 | **15.95** | **15.95** | 3.8e-6 |
| 7.14.1 (7.14.60850) | 2026-08 | 3.8e-6 | 3.8e-6 | 3.8e-6 | 3.8e-6 |
| 10.0.0 (7.15.26333) | 2026-08 | 3.8e-6 | 3.8e-6 | 3.8e-6 | 3.8e-6 |
| 10.1.0 (7.16.26385) | 2026-10 | 0 / 3.8e-6 | 3.8e-6 | 3.8e-6 | 3.8e-6 |
| 10.2.0 (7.17.26434) | 2026-11 | 3.8e-6 | 3.8e-6 | 3.8e-6 | 3.8e-6 |

7.1.1, 7.0.2 and 6.4.4 cannot compile Warp's headers ("an attribute list cannot appear here" in tile.h), so they are untested. 7.2.3 and 7.14.0 were not run.

**Result:** the defect is present in every 7.2 point release tested and absent from 7.14.1 onward. The `hipRuntimeGetVersion() < 71600000` gate is therefore too broad: it also disables SLP on 7.14 and 10.0, which are correct. `< 71400000` matches the tested range.
