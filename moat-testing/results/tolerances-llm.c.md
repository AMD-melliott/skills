# Why the llm.c ports loosen test tolerances on AMD, and why that is acceptable

Written for reuse in PR descriptions and feedback. Applies to llm.c `test_gpt2.cu` at upstream
`f1e2ace`, ported to HIP and run on MI300X (gfx942) with ROCm 7.2.1 and 10.1.0.

## What changes

Only on AMD builds (`#if defined(__HIP_PLATFORM_AMD__)`); the CUDA thresholds are untouched.
Three independent blind ports arrived at nearly the same values:

| Check | Upstream (CUDA) | Run 1 | Run 2 | Run 3 | Measured on MI300X |
|---|---|---|---|---|---|
| BF16 `ln2w` gradient threshold | 5e-2 | 6e-2 | 6e-2 | 7e-2 | one element of 9,216 (layer 11) at 1.008x the 5e-2 limit (diff 0.0623 vs 0.0618 allowed); every other BF16 tensor passes unchanged |
| FP32 gradient absolute floor (relative 7.9% term unchanged) | 1e-6 | 3e-5 | 5e-5 | 4e-5 | max abs diff 1.4e-5 to 1.8e-5; 533 of ~124M elements over 1e-6, all near zero, spread over all 16 tensors |
| FP32 logit threshold | 1e-3 | 2e-3 | 2e-3 | 2e-3 | max diff 1.03e-3 to 1.31e-3 |
| FP32 step-loss threshold | 1e-5 | 1e-4 | 2e-4 | 2e-4 | drift 5e-5 to 8e-5 after 5-10 AdamW steps |

`test_gpt2fp32cu` (the separate FP32 program) needed no change in any run. The BF16 build is the
default; `PRECISION=FP32` is a non-default build of the same test.

## Why these are rounding differences, not port bugs

1. **Upstream says its thresholds are hardware-specific and hand-set.** `test_gpt2.cu:259-266`:
   "I set the tolerances manually by inspecting the gradient differences for a few elements of
   each tensor ... if code changes and some of these get tripped, it could be ok if it's not by too
   much, because our use of stochastic rounding is adding some non-determinism ... it's ok to extend
   the tolerance by a bit, after a manual review. Also, different GPUs may use different matrix
   multiplication algorithms, so the actual errors can be hardware specific." The last upstream
   commit to the file (`42aa891`, 2025-04-13, "adjusted error thresholds") retuned them.
2. **Upstream's own CPU FP32 implementation fails the same FP32 thresholds.** Measured with the
   identical check metric: `test_gpt2.c` misses the 1e-6 floor on 13 of 16 gradient tensors (worst
   `ln1b` 10.5x, `ln1w` 2.7x; MI300X: 14x and 2.6x), and its logits differ from the PyTorch
   reference by 1.27e-3 against MI300X's 1.31e-3, with the same systematic offset. A correct FP32
   implementation that is not the reference GPU's operation order lands here.
3. **The GEMMs are true FP32.** hipBLASLt FP32 GEMM checked against a double-precision host
   reference: ~1e-7 relative to the summed term magnitudes, i.e. no TF32/XF32 reduced precision.
4. **Not FMA contraction.** Rebuilding with `-ffp-contract=on` / `off` (clang's default is `fast`)
   left the differences essentially unchanged.
5. **The error is spread, not localised.** Over-floor elements are near-zero gradients spread evenly
   across all 16 tensors; the largest gradients agree to ~3e-4 relative. A kernel bug concentrates
   in the tensor whose kernel is wrong.
6. **A second, independent FP32 path agrees.** `test_gpt2fp32cu` (rocBLAS SGEMM, different
   kernels) shows the same logit offset (8.7e-4 to 1.3e-3) and the same ~1e-4 loss drift.
7. **The BF16 outlier is BF16 rounding.** At the one `ln2w` element over the limit, the FP32 build
   matches the reference to 5e-4 (-0.149782 vs -0.149706). The BF16 result depends on stochastic
   rounding, whose noise depends on the launch grid, which differs on MI300X (304 CUs).
8. **Deterministic and version-independent.** Identical results across reruns, across all five CI
   argument variants, and on both ROCm 7.2.1 and 10.1.0.
9. **The loosened values keep margin and still catch real bugs.** Worst tensor at 65-81% of the
   AMD thresholds. The real bugs found in these ports failed by far more: the missing
   `__threadfence()` produced `Nondeterminism! Loss mismatch at step 1: 6.937 vs 6.885` (loss off by
   5e-2, 250x the loosened 2e-4), and the `warpSize` overrun produced a memory fault.

## Caveats to state honestly

- BF16 `lnfw` sits at 99.5% of its **unchanged** threshold. Stable here, but another ROCm or
  hipBLASLt version could tip it; it is the first place to look if the BF16 test starts failing.
- No NVIDIA run was possible on this host, so "CUDA passes these thresholds" rests on upstream CI.
- Thresholds were tuned on one architecture (gfx942). A wave32 or other CDNA part may need its own
  review rather than inheriting these.

## Suggested PR wording

> On AMD GPUs the test uses slightly wider tolerances, set under `__HIP_PLATFORM_AMD__` so the CUDA
> values are unchanged. As the comment above `grad_thresholds` notes, these are hardware-specific:
> measured on MI300X the FP32 logits differ from the reference by 1.3e-3, about the same as the
> repository's own CPU implementation (1.27e-3), and the remaining gradient differences are
> near-zero elements spread across all tensors. hipBLASLt runs these GEMMs in true FP32 (checked
> against a double-precision reference), and disabling FMA contraction does not change the result.
> In BF16 a single `ln2w` element is 0.8% over its limit; the FP32 build matches the reference there.
