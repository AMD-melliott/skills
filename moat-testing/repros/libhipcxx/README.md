# libhipcxx: `compare_exchange_strong` is weak at block/device scope (spurious failures, 1- and 2-byte types)

**Status: flagged for Matt. Not filed.** Found by the cuCollections blind port (2026-11-17); reproduced here
independently.

## Defect

In `include/cuda/std/__atomic/functions/atomic_hip_generated.h`, the block-scope and device-scope overloads of
`__atomic_compare_exchange_cuda(..., bool /*weak*/, ...)` ignore the weak flag and always call
`__hip_atomic_compare_exchange_weak`. As a result, `cuda::atomic_ref<T>::compare_exchange_strong` (and
`cuda::atomic`) can fail even though the value equals `expected`.

On AMDGPU a 1- or 2-byte CAS is lowered to a 32-bit CAS on the containing word. The weak form gives up
when any *neighbouring* byte in that word changes; the strong form retries.

## Repro (`cas.hip`)

Each thread owns one element and flips it 0→1→0 with `compare_exchange_strong`, 1000 times. No other
thread writes that element, so a strong CAS must never fail. The run is 1024 blocks × 256 threads, giving
524,288,000 CAS per row.

| Implementation (MI300X gfx942) | ROCm 7.2.1 | ROCm 10.1.0 |
|---|---|---|
| libhipcxx `832dc407f` (amd-develop, 2026-11-17), `atomic_ref<uint8_t>` strong | 393,216,000 spurious failures (75%) | same |
| same, `uint16_t` | 262,144,000 (50%) | same |
| same, `uint32_t` | 0 | 0 |
| **ROCm 10.1.0 bundled** `/opt/rocm/core-10.1/include/hipccl` (CCCL 3.0.2), `uint8_t` / `uint16_t` | n/a | 75% / 50% (same bug, shipping) |
| libhipcxx `90b6a2b57` (`release/26.10`, 2026-10-23) | source has the same weak-flag-ignoring overloads at block and device scope (not run: its headers need defines from its own CMake build) | same |
| raw `__hip_atomic_compare_exchange_strong` (`uint8_t` / `uint16_t`) | 0 / 0 | 0 / 0 |
| raw `__hip_atomic_compare_exchange_weak` (`uint8_t` / `uint16_t`) | 75% / 50% | same |
| libhipcxx with the cuco port's patch (`patched/`: honour the weak flag) | 0 / 0 / 0 | 0 / 0 / 0 |

Triage:

- The compiler builtins behave correctly, so the defect is in the libhipcxx wrapper.
- The skill's dtype and SP/DP triangulation do not apply to an atomics bug. The isolating check is the
  builtin comparison above.

```bash
# in this directory (unpatched libhipcxx checked out at 832dc407f in ./libhipcxx)
rocm-run [--image rocm/dev-ubuntu-24.04:10.1.0-full] bash -lc \
  'hipcc -std=c++20 --offload-arch=gfx942 -O2 -I libhipcxx/include -o /tmp/cas cas.hip && /tmp/cas'
```

## Impact seen

cuCollections `static_set<int8_t/int16_t>` loses or duplicates keys. Its insert treats a failed CAS on
an empty slot as "taken", which gave 11 failing test cases (e.g. `count == 398` instead of 400).

## Fix

Use `__hip_atomic_compare_exchange_strong` when the weak flag is false, for both scopes. The patch is
`../../projects/cuCollections/cmake/hip/patches/libhipcxx_strong_cas.diff`. It is about 10 lines and
was validated above.

## Related (same file, compile-time): `../libhipcxx-align/`

`atomic_ref<T>` on an 8-byte type with `alignof(T) == 4` (`struct {int a, b;}`, which callers align to 8
as `atomic_ref` requires) fails to build:

- ROCm 7.2.1: `error: unsupported cmpxchg`
- ROCm 10.1.0: `ld.lld: error: unsupported cmpxchg: instruction alignment 4 is smaller than the
  required 8-byte alignment`

The cuco port's `libhipcxx_atomic_alignment.diff` makes it build and run correctly (`{1,2}`).
NVIDIA's libcu++ (CUDA 12.8, nvcc, sm_90) compiles the same code, so this is a libhipcxx portability gap.
