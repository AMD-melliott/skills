# Baseline: skill evals (unmodified skill)

- Date: 2026-11-17
- Skill: `AMD-melliott/skills` branch `moat-testing` at `upstream/main` (no edits yet), `skills/moat-cuda-to-rocm`
- Harness: one fresh headless `claude -p` per eval (Claude Code 2.1.326, Opus 5.5), empty working
  dir, all plugins disabled, no MCP, tool allowlist `Read,Write,Edit,Glob,Grep,Skill,WebSearch,WebFetch`
  (no Bash). Transcripts: `evals/baseline/<id>/transcript.jsonl`.
- Grader: me, against `expected_behavior` / `unexpected_behavior` / `files_exist` / `skill_should_trigger`.

## Summary

| Eval | Trigger expected | Skill invoked | Graded items | Result |
|---|---|---|---|---|
| review-kernel-for-wave64 | yes | yes | 4/4 expected, 0/2 unexpected | PASS (file-location caveat) |
| plan-torch-extension-port | yes | yes | 2/2 expected, 0/2 unexpected | PASS |
| hip-port-misbehaves-at-runtime | yes | yes | (no rubric) | PASS (trigger) |
| add-amd-build-to-cmake-cuda-project | yes | yes | (no rubric) | PASS (trigger) |
| cuda-bank-conflicts-on-rtx | no | no | - | PASS |
| pytorch-cuda-to-apple-mps | no | no | - | PASS |
| cuda-kernel-to-cpu-openmp | no | no | - | PASS |

Cost: about $1.02 total, 9-55 s per eval.

## Per item

### review-kernel-for-wave64

| Item | Verdict | Evidence (review.md) |
|---|---|---|
| E1 hardcoded 32 wrong on wave64; derive from warpSize, do not hardcode another constant | PASS | Findings 3 and 4: "use `warpSize`" in device code, runtime query on host, "Don't replace 32 with a hard-coded 64" |
| E2 32-bit mask fails HIP's 64-bit static_assert even though hipify ran clean; mask 64-bit on HIP, 32-bit on CUDA | PASS | Finding 1, quotes the static_assert text, gives `FULL_MASK` split on `__HIP_PLATFORM_AMD__` |
| E3 ballot cast to 32 bits keeps half of wave64 | PASS | Finding 2; also catches the `% 32 == 0` double-leader and `__popc` vs `__popcll` |
| E4 counter never zeroed before atomicAdd | PASS | Finding 5 |
| U1 concludes ready because hipify clean | not present | |
| U2 hardcode 64 | not present | explicitly warns against it |
| files_exist review.md | **PASS with caveat** | The agent wrote `/mnt/data/.../review-kernel-for-wave64-work/work/review.md`: it mistyped its own cwd (`-work` appended). A strict cwd check would fail. Agent slip, not a skill issue; noted in case it recurs. |

### plan-torch-extension-port

| Item | Verdict | Evidence (plan.md) |
|---|---|---|
| E1 PyTorch extension, rely on torch build-time hipify, fix only what it cannot | PASS | "Approach": keep CUDA spelling, `CUDAExtension` hipifies at build time, fixes behind `USE_ROCM` |
| E2 done only when tests pass on a real AMD GPU | PASS | "Compiling cleanly without a GPU is not evidence the port works." |
| U1 standalone CMake + compat header as primary | not present | "Don't add a compat header" |
| U2 commit hipified copies | not present | |

### hip-port-misbehaves-at-runtime / add-amd-build-to-cmake-cuda-project

No rubric in `evals.json` (trigger only). Both answers drew on the skill's index and the right
reference (Strategy A recipe with shim headers, `CMAKE_PREFIX_PATH`, no pinned arch; runtime
answer led with wave64-vs-wave32, unzeroed memory, OOB, `-ffp-contract`, host min/max, SP-vs-DP style check).

## Observations

- Baseline is saturated: the existing evals do not discriminate. Every graded item passes on
  the unmodified skill, so they cannot show an improvement and can only catch a regression.
  New evals added in this effort need to be ones the baseline skill can fail.
- `hip-port-misbehaves-at-runtime` answer recommends "Use `fminf`/`fmaxf`" for host min/max,
  i.e. it followed the second of the two contradictory SKILL.md lines (known gap 2), not the
  `__HIP_DEFINE_EXTENDED_HOST_MIN_MAX__` one. The contradiction is still in the index.
- Two evals have no `expected_behavior`; they only test triggering.

---

# After iteration 1 (llm.c): full eval set on the updated skill

- Skill: branch `moat-testing` @ `083f692` (8 commits on top of upstream `3e41c08`). 11 evals (7 original + 4 new).
- Transcripts: `evals/after-iter1/<id>/`.

| Eval | Trigger | Result |
|---|---|---|
| review-kernel-for-wave64 | yes / invoked | PASS 4/4, no unexpected (again also wrote a stray copy to a mistyped `...-work/` path; real file present in cwd this time) |
| plan-torch-extension-port | yes / invoked | PASS 2/2, no unexpected |
| host-min-max-in-shared-code (new) | yes / invoked | PASS 4/4 |
| review-reduction-kernels-for-mi300x (new) | yes / invoked | PASS 4/4 |
| compat-shim-stand-in-across-rocm-releases (new) | yes / invoked | PASS 3/3 |
| existing-amd-fork-linked-in-readme (new) | yes / invoked | PASS 4/4 |
| hip-port-misbehaves-at-runtime | yes / invoked | PASS (trigger) |
| add-amd-build-to-cmake-cuda-project | yes / invoked | PASS (trigger) |
| cuda-bank-conflicts-on-rtx, pytorch-cuda-to-apple-mps, cuda-kernel-to-cpu-openmp | no / not invoked | PASS |

No regression. The 4 new evals also passed on the UNMODIFIED skill (min/max 3/3 runs; the other three 2/2 runs each),
so they are regression guards only. Review- and plan-shaped prompts point the agent at the
suspect code; the blind port missed the same faults for process reasons (never ran a large config,
never built on a second ROCm release, never acted on the README fork link). Only the blind re-run
measures whether the skill edits change behaviour.
