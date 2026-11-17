# llm.c control run: original skill + current env notes (ROCm 10.1 confound)

- **Purpose:** Item 2 of the review. Runs 2 and 3 used env notes that named ROCm 10.1 as the current
  release; run 1's did not. This run separates the skill edits from that wording.
- **Setup:** llm.c `f1e2ace`; skill pinned to upstream `3e41c08` (unmodified); env notes byte-identical to
  runs 2/3 (`prompts/env-notes.md`); same request, harness and allowlist as runs 1-3.
- **Run:** 2026-11-17 13:41-14:14 (34 min), 120 turns, $6.28, exit 0. Transcript
  `transcripts/llm.c-control/`, project `projects/llm.c-control/`, scoring copy `tmp/llm.c-control-score/`.

## Independent verification (my rebuild, scoring copy, GPU 7)

`tools/llmc-matrix.sh` (BF16 and FP32 `test_gpt2cu` x 5 CI variants, plus `test_gpt2fp32cu`):

| | ROCm 7.2.1 | ROCm 10.1.0 |
|---|---|---|
| builds (all targets) | yes | yes |
| `test_gpt2fp32cu` | PASS | PASS |
| BF16 `test_gpt2cu` x5 | FAIL, 1 tensor (`ln2w`, 100.77% of limit) | same |
| FP32 `test_gpt2cu` x5 | FAIL, 14 tensors + logits (1.03e-3 vs 1e-3) | same |

The failures have the same signature as runs 1-3 before their AMD-only tolerance widening
(`results/tolerances-llm.c.md`): BF16 `ln2w` 0.8% over; FP32 gradient abs diffs 1.2e-5 to 4e-4 with
relative error ~1e-4 to 5e-3; logits 1.03e-3; step losses match. This agent deliberately did **not** widen
tolerances, and its PORT_SUMMARY says so and leaves the decision to the user, with supporting
evidence: three references, an isolated hipBLASLt check, and an FMA-contraction test. That is
arguably better practice than runs 1-3. Comparable to runs 1-3: **pass apart from the known tolerance
question**. The nvcc gate was run by the agent (all CUDA targets, BF16+FP32); I did not re-run it.

## Behaviour per evidenced gap

| Gap (skill commit) | Run 1 (old skill, old notes) | Runs 2/3 (new skill, 10.1 notes) | Control (old skill, 10.1 notes) | Attribution |
|---|---|---|---|---|
| Validate on current ROCm; gate stand-ins (bc37f9a) | 7.2.1 only; `cg::plus` collides on 10.1 | both; gated | **both; gated on `hip_reduce.h`** (found on 10.1 at step 108, fixed) | **env notes, not the skill edit.** bc37f9a is unproven |
| Existing-port verdict (c988011) | link seen, ignored | verdict recorded | **verdict recorded** ("treated as a hint only, no code taken") | **not demonstrated:** run-to-run variance or the notes. Unproven |
| warpSize OOB (existing skill text) | runtime | anticipated | **predicted before running** | old skill can already do this |
| Fence in last-block reduction (8bc499a) | runtime | anticipated | runtime (fixed after the first GPU test) | still favours the edit, n=1 each |
| Grid from device props (bdeabb0) | runtime | anticipated | runtime | still favours the edit, n=1 each |
| 64 KiB LDS + last error (8a332d8/f6f8243) | missed | run 2 missed, run 3 fixed | **missed** (`cudaCheck(cudaGetLastError())` after the opt-in unchanged; no large config run) | favours the f6f8243 revision, n=1 |
| Host min/max (c885c1b) | n/a | n/a | found at runtime; used `-D__HIP_DEFINE_EXTENDED_HOST_MIN_MAX__=1` | the old skill's index lines contradict each other; the control picked the working one |

## Conclusions

1. **The 10.1 result in iteration 1 was the env notes.** The old skill, told that 10.1 is current, built
   and tested on it and version-gated the stand-in by itself. bc37f9a's "validate on the current ROCm
   release" clause had no measurable effect here. To test it at all, the env notes must stop naming a
   release as current (see the method change below).
2. **The fork-verdict edit (c988011) is not shown to matter.** The old skill recorded a verdict this time.
3. **Still favouring edits, each n=1:** fence and grid (anticipated only with the edits) and LDS (only
   run 3, after the revision).
4. **Not a regression signal:** the control made no tolerance changes, so its raw test results look
   worse than runs 1-3 but are numerically the same.

## Method change from here on (neutral env notes)

The env notes list available images without calling any release "current" or recommending one. The
skill alone must then decide which ROCm releases to validate on. The same notes are used for every
arm. bc37f9a and c988011 are held out of any upstream PR until a neutral-notes run shows an effect.
