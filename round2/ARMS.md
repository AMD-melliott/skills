# Round-2 skill arms, rebuilt on current moat main

Nothing was pushed, filed or run on a GPU or in a container. Both branches are local to
`/data/melliott/moat-testing/round2/moat`.

## Read this first: three things that need a decision

1. **Edit 5 is not fully verbatim: one word was changed so the gate passes.** In the
   `validation.md` fresh-clone bullet, "Neither was visible to the **porter**." is now
   "Neither was visible to the **port's author**." Main's widened `skills` gate (eae90aaf,
   "remove home-repository leakage and widen the gate") rejects `porter` as MOAT vocabulary:
   `validation.md:25: MOAT vocabulary 'porter'`. The brief requires both the verbatim text
   and a passing gate, so they cannot both hold. I used main's own substitution from
   eae90aaf ("the porters" -> "the port's authors" in assess-existing-support.md). The
   changed sentence is evidence, not a rule, and the rule sentences are untouched. To restore
   the original word, revert that one line; `skills` then fails on armB.
2. **The gate command as written fails on the base and on both arms, because of this host.** It fails
   only in `harness-adapters`, and the cause is the installed `codex` CLI (0.165.0, `~/.local/bin/codex`),
   whose login is dead: `codex features list` exits with "Your access token could not be refreshed
   because your refresh token was revoked". The gate runs that command to parse the Codex config.
   With `CODEX_HOME` pointed at an empty directory (`/tmp/codexhome.32ud`), the same command
   parses the config with no login, and all three gates pass on the base, armA and armB. The
   skill edits do not touch any Codex config. Someone should re-login codex on this host
   (`codex login`) and re-run the command as written.
3. **Edit 3 conflicts with main (recorded, not resolved).** Edit 3's new entry gates the
   cooperative-groups stand-ins on HIP 7.16:
   `#if HIP_VERSION_MAJOR < 7 || (HIP_VERSION_MAJOR == 7 && HIP_VERSION_MINOR < 16)`, and calls
   7.16 "the version that introduced the real thing". Main now says, in the passage just above
   (build-headers-macros.md, rewritten after 4f2c9a7f): "That header is present from ROCm 7.13
   and absent in every 7.2.x release (through 7.2.4), so the `USE_ROCM` arm must not be a plain
   include: use `#if __has_include(<hip/cooperative_groups/hip_reduce.h>)`". Read literally, the
   HIP-7.16 gate would keep the stand-ins on ROCm 7.13/7.14, which already ship `hip_reduce.h`.
   Main does not say whether 7.13/7.14 also ship `cg::plus`/`less`/`greater`, which is what
   collides. The edit is carried verbatim; its own "or on a feature test where the header
   provides one" is compatible with main's `__has_include`. Nothing was changed to reconcile
   the two.

## Identity

- BASE_SHA: `e9c7958ba976d3bd99effb735684f1865a3f10be` (= `origin/main` in the clone)
- armA = `round2/armA`, HEAD `c762801707ae9de381afb9c28f1af935569affc3`,
  tree `496c48730fa6aabfb86a2a70fb163c2377e46b9d`
- armB = `round2/armB`, HEAD `e37e7d8e0db50c08f0f3770c3fbafd78595b3a2d`,
  tree `68b13eacfc95e5d30445af3bbb080f16fb931142`

| # | edit | branch | commit |
|---|---|---|---|
| 1 | fault-classes | armA, armB | `a620b2aaedde7cc826094c5ec7d4a5a25dc7b98e` cuda-to-rocm: MI300X fault classes found by three independent ports |
| 2 | rocm-721-slp-miscompile | armA, armB | `e707f682bdb8e2e876e07b762edc180da7c12df3` cuda-to-rocm: ROCm 7.2.1 SLP-vectorizer miscompile and its version gate |
| 3 | rocm-version-validation | armA, armB | `c762801707ae9de381afb9c28f1af935569affc3` cuda-to-rocm: validate on the current ROCm and at the largest size |
| 4 | existing-port-verdict | armB | `025e751917aac52927fe38a0d30874a4ee0e2f1e` cuda-to-rocm: act on the existing-port check; ask before a parallel port |
| 5 | validation-process-rules | armB | `e37e7d8e0db50c08f0f3770c3fbafd78595b3a2d` cuda-to-rocm: plan the validation matrix; validate from a fresh clone |

The commit titles match the fork branches. Each body is the fork body adjusted to the new
file names, ends with "Authored with Claude.", and has no Co-Authored-By trailer. The Test
Plan names the gate command. Before starting, I confirmed that the fork refs
`fork/moat-pr/<name>` reproduce the five diff files byte for byte (`git diff 4f2c9a7f
fork/moat-pr/<name>`, and rocm-version-validation..validation-process-rules for edit 5). The
eval objects were copied from those refs by id.

## Conventions followed (apply to all edits)

- **SKILL.md's hand-written fault index no longer exists.** Main replaced it with an index
  generated from entry titles (`utils/gen_skill_index.py`, checked by `check.py skills`).
  Every old-diff hunk that added or changed a one-liner in that index (edits 1, 2, 3, 5) has no
  place to go. Its content is carried by the reference entry, and the index line is
  regenerated from that entry's bold title. For each such one-liner I confirmed that every fact
  in it is also in the reference entry it pointed to. The index was regenerated with
  `MOAT_LOCAL_TOOLS=1 uv run --python 3.13 python utils/gen_skill_index.py` after each edit and
  never edited by hand.
- **Evals:** main keeps the positive evals before the negative (`skill_should_trigger: false`)
  ones, but the old diffs appended theirs after the last negative. The new evals go after the
  last positive eval, in the order of the diffs. The objects are unchanged, and the file is
  re-serialised with `json.dumps(indent=2)`, which reproduces main's file byte for byte.
- **Source tags:** main ends entries with a `(project)` tag. Edits 1 and 2 had three entries
  with no trailing tag; `(cuCollections)` was added to the host-shadow and libhipcxx entries,
  and `(Warp)` to the SLP entry. Each project was already named in the entry's text. Edits 4
  and 5 got no tags because their text is carried verbatim.
- **Placement:** each entry was placed next to the same neighbour it had in the old
  `fault-classes.md`, inside the topic file that now holds that neighbour.

## Edit 1 -- fault-classes (armA commit 1)

| old location | new location |
|---|---|
| SKILL.md index, wavefront: "Fixing that count is not enough..." | dropped (generated index); index now has "The shuffles themselves read lanes that hold no thread, whatever the count says" |
| SKILL.md index, memory: "A 'last block to finish reduces...'" | dropped; index line "A "last block reduces" kernel needs `__threadfence()`..." |
| SKILL.md index, memory: "Host code that reads a `__device__` variable..." | dropped; index line "Host code reading a `__device__` variable through a pointer gets HIP's host shadow..." |
| SKILL.md index, textures: "gfx94x (MI300-class) has NO image/texture support..." | dropped: **already upstream**, see below |
| SKILL.md index, floating point: host min/max line rewritten | dropped; index line becomes "Host `min`/`max` on floating-point or unsigned values truncate to int under hipcc" |
| SKILL.md index, platform: "Sizes derived from device properties grow on MI300X..." | dropped; index line "Launch geometry computed from device properties can overshoot..." |
| SKILL.md index, platform: "LDS (shared memory) is capped at 64 KiB..." | dropped; index line "Shared memory (LDS) per block tops out at 64 KiB on gfx942..." |
| SKILL.md index, libraries: "libcu++ -> libhipcxx (...)" | a new row in the substitution table, `references/libraries.md` "Substitution table" (that table replaced SKILL.md's "Library swaps" line, which this one-liner extended) |
| fault-classes.md wavefront, after the CV-CUDA narrow-block entry: "The shuffles themselves..." | `references/faults-wavefront.md`, "Choosing the width", directly after the same CV-CUDA entry, verbatim |
| fault-classes.md, after TIGRE `CreateTextureParallel`, before the functor entry: "Host code reading a `__device__` variable..." | `references/faults-memory-streams.md`, "Handle and object lifetime", directly before the functor entry (its old following neighbour; TIGRE now sits in another section), verbatim + `(cuCollections)` |
| fault-classes.md, after TornadoVM D2D copy entry: "A 'last block reduces' kernel needs `__threadfence()`..." | `references/faults-memory-streams.md`, "Copies and stream ordering", directly after the same TornadoVM entry, verbatim |
| fault-classes.md gfx94x texture entry: runtime sentence | `references/faults-textures-interop.md`: only the new facts were fitted into main's existing runtime sentence (see below) |
| fault-classes.md "Host `min`/`max`..." (title, unsigned/64-bit text, measurements, macro paragraph, static_assert) | `references/faults-numerics.md`, "Host math under the HIP compiler". The entry on main is byte-identical to the old base, so all three hunks apply as they were |
| fault-classes.md, end of the section before "Types, dispatch and platform limits": launch geometry + LDS entries | `references/platform-limits.md`, "Device queries and counters", after "On RDNA, a nonzero occupancy does not mean the dynamic shared memory fits" (the per-block LDS limit on RDNA), verbatim except the path below |
| fault-classes.md "Types, dispatch and platform limits", before "Library swaps": libhipcxx entry | `references/libraries.md`, end of "rocThrust, hipCUB and rocPRIM" (the CCCL family), verbatim + `(cuCollections)` |
| evals.json, 5 evals | `evals/evals.json` (ids: host-min-max-in-shared-code, review-reduction-kernels-for-mi300x, review-warp-reduce-small-blocks, review-small-key-atomic-insert-libhipcxx, review-host-finalizer-device-tables) |

Path change: in the launch-geometry entry, "`__smid()` exceeding `multiProcessorCount`
(wavefront section)" became "(faults-wavefront.md)".

**Already upstream, so dropped (texture runtime facts).** Main's `faults-textures-interop.md`
already says: "It is not only a compile-time macro. On the hardware (MI300X, ROCm 7.14),
`hipMallocArray` and `hipCreateTextureObject` both return `hipErrorNotSupported` ("operation
not supported"), ... (`hipDeviceAttributeImageSupport` is the query that answers)". On a
software path it says: "**A project that reads EVERYTHING through texture objects, with address
modes, needs more than a pointer swap.**" and "supporting gfx94x means replacing texture
objects with buffer reads". For the SKILL.md one-liner, main's router row is "textures (also
`tex*` compile errors on gfx94x)" and its index line is "gfx94x+ (CDNA3 and newer:
MI300-class) disables the HIP image/texture object API at ...". What edit 1 added beyond
that, and what was kept: `hipDeviceAttributeImageSupport` = 0 stated outright, "(even for a
linear resource)", and the measurement on ROCm 7.2.1 and 10.1.0. These were fitted into main's
sentence: "On the hardware (MI300X, ROCm 7.14; also measured on ROCm 7.2.1 and 10.1.0),
`hipDeviceAttributeImageSupport` is 0, and `hipMallocArray` and `hipCreateTextureObject` (even
for a linear resource) both return ...". Dropped as upstream: "a sample that reads through
`cudaArray`s with address modes and filtering needs a software texture path on these GPUs".
*Unsure:* main's emulation entry covers address modes but says it is exact only "when no
binding relies on hardware filtering", so the word "filtering" is not fully covered upstream.

Other notes / uncertainty:
- The libcu++ table row (`| libcu++ | libhipcxx | yes | ...`) summarises facts from the edit.
  It is the new home of the edit's SKILL.md line, so it is not new content, but its wording is
  mine.
- I chose the libhipcxx section ("rocThrust, hipCUB and rocPRIM") myself. The old location
  (just before "Library swaps") maps to the top of libraries.md, which is now the substitution
  table section.
- Not a conflict, but worth knowing: main's RDNA occupancy entry says that on gfx1100
  `hipFuncSetAttribute(MaxDynamicSharedMemorySize)` "succeeds and is not enforced". Edit 1
  measures it returning `hipErrorInvalidValue` above 64 KiB on gfx942. Different
  architectures, so both stand.
- Main's CV-CUDA entry already says "Ceil-dividing the count is not enough, because it leaves
  the out-of-block shuffles". It said the same at the old base, so the edit was written
  against it and was kept.

## Edit 2 -- rocm-721-slp-miscompile (armA commit 2)

| old location | new location |
|---|---|
| SKILL.md index, floating point: "ROCm 7.2.1's device compiler miscompiles..." | dropped (generated index); index line "A device result that is wrong only at -O2/-O3 on ROCm 7.2.1 and right at -O0/-O1 may be ..." under diagnosis.md |
| validation.md "Two patterns that each cost a deep investigation", bullet after cuSZ | `references/diagnosis.md`, "Method", directly after the same cuSZ entry. That list became bold paragraphs, so the leading "- " was dropped and `(Warp)` appended; the text is otherwise verbatim |
| evals.json | `evals/evals.json` (id opt-level-dependent-wrong-result-rocm72) |

Nothing was already upstream (main has no "slp" or "hiprtcVersion" text), and nothing conflicts.

## Edit 3 -- rocm-version-validation (armA commit 3)

| old location | new location |
|---|---|
| SKILL.md index, headers: "A compat stand-in for an API one ROCm release lacks collides..." | dropped (generated index); index line "A stand-in for an API HIP lacks must be gated, because a later ROCm adds it" |
| SKILL.md "Validation bar": two sentences after "...when the project builds there." | SKILL.md "Validation bar", same place, verbatim. The paragraph was re-wrapped because main had already re-flowed it, and main's "no-regression check" (was "gate") is kept |
| fault-classes.md, after the colmap cooperative-groups entry: stand-in entry | `references/build-headers-macros.md`, after the cooperative-groups passage (after main's added `cg::grid_group` CuRast paragraph, so that paragraph stays attached to its entry), verbatim |
| validation.md, two bullets after the CPU-only docker bullet | `references/validation.md` "Validation policy", same place, verbatim except the path below |
| evals.json | `evals/evals.json` (id compat-shim-stand-in-across-rocm-releases) |

Path change: "(see the LDS entry in fault-classes.md)" became "(see the LDS entry in
platform-limits.md)". The "Orochi" threshold note the commit body mentions is still in
faults-wavefront.md.

**Conflict:** see item 3 at the top (HIP 7.16 gate vs main's "present from ROCm 7.13").

**Partly upstream:** main already gates the `cg::reduce` include, as quoted in item 3. What the
edit adds is the `cg::plus`/`less`/`greater` redefinition on HIP 7.16 and the general rule
for stand-ins. Nothing was dropped, because no sentence of the edit is already on main.

## Edit 4 -- existing-port-verdict (armB commit 4, experimental treatment)

| old location | new location |
|---|---|
| SKILL.md "Before porting", after the assess-existing-support paragraph: "Running the grep is not the check..." and the bold stop-and-ask paragraph | SKILL.md "Before porting", after main's (rewritten) first paragraph, before the no-hip-equivalent paragraph. **Verbatim** |
| assess-existing-support.md, before "Then classify what you found:" | same file, same place. **Verbatim** (the surrounding lines are unchanged on main) |
| evals.json | `evals/evals.json` (id existing-amd-fork-linked-in-readme) |

*Unsure (left as is, because the text must be verbatim):* main rewrote the first "Before
porting" paragraph, and the old sentence "Cheapest high-signal check first: grep the
upstream's own docs for `amd|rocm|hip|gfx[0-9]`, because reference repos routinely link
platform forks." is no longer in SKILL.md. The grep is now only step 1 of
`references/assess-existing-support.md`. So in armB's SKILL.md, "Running the grep is not the
check" points back to a grep that SKILL.md itself no longer mentions. "the reference" in "a
web search from the reference" still resolves, since the paragraph above names
`references/assess-existing-support.md`. I did not restore the removed sentence, because
that would add text beyond the diff.

Overlap with existing text (not new on main, and not dropped): assess-existing-support.md line 4 already
says "A repo that LINKS platform forks rather than merging them does not want an upstream
platform PR even for a real delta -- contribute to the linked fork." That line was there at
the old base too, so the edit was written against it. The edit's SKILL.md sentence repeats
the idea, as it did originally.

## Edit 5 -- validation-process-rules (armB commit 5, experimental treatment)

| old location | new location |
|---|---|
| SKILL.md index, headers: "Upstream ignore rules can swallow port files..." | dropped (generated index); index line "Upstream ignore rules can silently drop port files" under build-cmake-link.md |
| SKILL.md, two paragraphs after the "Validation bar" paragraph (matrix-first, fresh clone) | same place (before "## Keeping an open PR mergeable"). **Verbatim** |
| fault-classes.md, before "A force-included compat header creates no build dependency edge": ignore-rules entry | `references/build-cmake-link.md`, directly before the same entry (now the first entry of "Which files compile as HIP"). **Verbatim**, no tag added |
| strategy-b-torch.md, first bullet of the dependency-environment list | same file and place (before "A pip install silently overwrites the ROCm torch."). **Verbatim** |
| validation.md, bullet after the ROCm-versions bullet | `references/validation.md` "Validation policy", same place. **Verbatim except one word: "porter" -> "port's author"** (item 1 at the top) |
| evals.json | `evals/evals.json` (ids torch-extension-validation-matrix, pr-checklist-port-with-patch-files) |

The references still resolve: "The strategy-b note on staging files before `build_py`" is
`strategy-b-torch.md`'s last bullet ("...must be staged BEFORE `build_py`..."), and "The
validation bar's current-ROCm leg" is the SKILL.md sentence from edit 3.

*Unsure:* placing the ignore-rules entry under "Which files compile as HIP" keeps its old
neighbour, but its topic would sit as well under "Installed packages and optional targets".
I kept the neighbour.

## Gate output

The command, run on each arm head from a clean checkout:

```
MOAT_LOCAL_TOOLS=1 uv run --python 3.13 python utils/check.py skills harness-adapters jargon
```

| | as specified | with `CODEX_HOME=/tmp/codexhome.32ud` (empty dir) |
|---|---|---|
| base e9c7958b | skills ok; harness-adapters FAIL ("Codex refuses this checkout's config: Error: failed to load configuration"); jargon ok | skills ok; harness-adapters ok; jargon ok |
| armA c7628017 | same as base (exit 1, harness-adapters only) | skills ok; harness-adapters ok; jargon ok (exit 0) |
| armB e37e7d8e | same as base (exit 1, harness-adapters only) | skills ok; harness-adapters ok; jargon ok (exit 0) |

The underlying error is `codex features list` -> "Your access token could not be refreshed
because your refresh token was revoked." `utils/gen_skill_index.py --check` reports the
index current on both heads. The evals file holds 17 evals on the base, 24 on armA and 27 on
armB, and each parses as JSON. Before the one-word change, the `skills` gate on edit 5 had
failed with `validation.md:25: MOAT vocabulary 'porter'`.

## armA..armB

```
$ git diff round2/armA round2/armB --stat
 .claude/skills/cuda-to-rocm/SKILL.md               | 25 +++++++++++
 .claude/skills/cuda-to-rocm/evals/evals.json       | 48 ++++++++++++++++++++++
 .../references/assess-existing-support.md          |  2 +
 .../cuda-to-rocm/references/build-cmake-link.md    | 10 +++++
 .../cuda-to-rocm/references/strategy-b-torch.md    |  1 +
 .../skills/cuda-to-rocm/references/validation.md   |  1 +
 6 files changed, 87 insertions(+)
```

These are exactly the files edits 4 and 5 touch: SKILL.md, evals.json,
assess-existing-support.md, strategy-b-torch.md and validation.md, plus build-cmake-link.md
as the new home of edit 5's fault-classes.md hunk. The diff only adds lines; nothing is
deleted or modified. I compared the sorted added lines of `git diff round2/armA round2/armB`
with the added lines of existing-port-verdict.diff and validation-process-rules.diff. Every
line is identical except two. (a) The diffs' hand-written SKILL.md one-liner "- Upstream
ignore rules can swallow port files: ..." is replaced by the generated index line "- Upstream
ignore rules can silently drop port files". (b) The validation.md bullet reads "port's author"
where the diff has "porter". Reading the whole diff confirms it holds only edit 4 (the two
SKILL.md "Before porting" paragraphs, the assess-existing-support paragraph, one eval) and
edit 5 (the two SKILL.md validation-bar paragraphs, the ignore-rules entry and its index line,
the torch-ROCm bullet, the fresh-clone validation bullet, two evals). No edit 1-3 text appears.
The same comparison for BASE..armA against diffs 1-3 shows only the differences recorded
above: generated index lines instead of one-liners, re-wrapping, path fixes, source tags, the
texture fit, the table row, and diagnosis paragraph form.

## Projects named in arm B (BASE..armB added lines)

Line numbers are in the armB tree, under `.claude/skills/cuda-to-rocm/`. "edit 4/5" lines are
the treatment (armA..armB); "edit 1-3" lines are inherited from armA and are therefore present
in both arms.

- `SKILL.md:395` [[edit 1-3, inherited from armA]] **libhipcxx** -- - libcu++ -> libhipcxx, and two atomic defects in it
- `evals/evals.json:222` [[edit 1-3, inherited from armA]] **libhipcxx** -- "id": "review-small-key-atomic-insert-libhipcxx",
- `evals/evals.json:224` [[edit 1-3, inherited from armA]] **libhipcxx** -- "prompt": "Our open-addressing set works on CUDA. For AMD we build it against libhipcxx (the copy that ships with ROCm 10.1) and target MI300X. Tests with 32-bi
- `evals/evals.json:226` [[edit 1-3, inherited from armA]] **libhipcxx** -- "Identify that libhipcxx's compare_exchange_strong at device/block scope is implemented with the weak HIP builtin, so for 1- and 2-byte keys (emulated with a 32
- `evals/evals.json:227` [[edit 1-3, inherited from armA]] **libhipcxx** -- "Explain that the insert treats that spurious failure as 'slot taken' and probes on, so the same key can be inserted twice or the slot left empty, matching the 
- `evals/evals.json:231` [[edit 1-3, inherited from armA]] **libhipcxx** -- "Present the weak-CAS behaviour only as an unconfirmed possibility to check (e.g. 'if libhipcxx's emulation behaves like a weak CAS'), or rank another cause fir
- `evals/evals.json:288` [[edit 4/5, armA..armB]] **anthonix, llm.c** -- "prompt": "We want to port an open-source CUDA LLM training repo to AMD MI300X. Its README has a 'notable forks' section that includes: '- AMD support: [llm.c](
- `evals/evals.json:321` [[edit 4/5, armA..armB]] **libhipcxx** -- "prompt": "I've finished a HIP port of a CMake CUDA library in my working tree (tests pass on MI300X). Write pr-steps.md: the exact steps to turn this working t
- `references/assess-existing-support.md:10` [[edit 4/5, armA..armB]] **cuCollections, dynamic_map, hipCollections, HyperLogLog, ROCm-DS** -- Finding the AMD effort is not where this goes wrong; acting on it is. Two independent ports of NVIDIA cuCollections both found ROCm/hipCollections (part of ROCm
- `references/build-cmake-link.md:21` [[edit 4/5, armA..armB]] **cuCollections, libhipcxx** -- the working tree still builds. In the cuCollections port the two libhipcxx patches were
- `references/build-headers-macros.md:377` [[edit 1-3, inherited from armA]] **llm.c** -- current release. (llm.c: a shim `cooperative_groups/reduce.h` built and passed on ROCm 7.2.1 and
- `references/build-headers-macros.md:378` [[edit 1-3, inherited from armA]] **test_gpt2fp32cu** -- failed to compile `test_gpt2fp32cu` on ROCm 10.1.0; gated as above, it built and passed on both.)
- `references/diagnosis.md:99` [[edit 1-3, inherited from armA]] **block_jacobi, Warp** -- **A device result that is wrong only at -O2/-O3 on ROCm 7.2.1 and right at -O0/-O1 may be the SLP-vectorizer miscompile, so bisect the flags before rewriting co
- `references/faults-memory-streams.md:118` [[edit 1-3, inherited from armA]] **cuCollections, HyperLogLog** -- the problem in small tests. Nothing faults: in cuCollections the HyperLogLog++ host finalizer
- `references/faults-memory-streams.md:119` [[edit 1-3, inherited from armA]] **Spark** -- silently skipped bias correction (Spark-parity test 79 vs. 81). Fix on HIP: drop `__device__` and
- `references/faults-memory-streams.md:122` [[edit 1-3, inherited from armA]] **cuCollections** -- (cuCollections)
- `references/faults-memory-streams.md:345` [[edit 1-3, inherited from armA]] **threadFenceReduction** -- CUDA's own threadFenceReduction sample does. Code that leaves the fences out usually works on an
- `references/faults-memory-streams.md:353` [[edit 1-3, inherited from armA]] **layernorm, llm.c** -- comments. Measured on gfx942 with ROCm 7.2.1 and 10.1.0 (llm.c `layernorm_backward_kernel10`,
- `references/faults-memory-streams.md:357` [[edit 1-3, inherited from armA]] **llm.c** -- both. (llm.c)
- `references/faults-wavefront.md:76` [[edit 1-3, inherited from armA]] **cuda-samples** -- (cuda-samples `reduction` `reduce7`/`warpReduceSum`.)
- `references/libraries.md:35` [[edit 1-3, inherited from armA]] **CCCL, libhipcxx** -- | libcu++ | libhipcxx | yes | `cuda::` spelling kept; ROCm 10.1 bundles CCCL 3.0.2 as `hipccl`; 1- and 2-byte CAS, under-aligned 8-byte `atomic_ref` ("rocThrust
- `references/libraries.md:243` [[edit 1-3, inherited from armA]] **libhipcxx** -- **libcu++ -> libhipcxx, and two atomic defects in it.** `ROCm/libhipcxx` keeps the
- `references/libraries.md:244` [[edit 1-3, inherited from armA]] **CCCL** -- `cuda::`/`cuda::std::` spelling, so CCCL-heavy code (`cuda::atomic_ref`, `cuda::stream_ref`,
- `references/libraries.md:245` [[edit 1-3, inherited from armA]] **CCCL** -- `cuda::std::span`) ports without renames. ROCm 10.1 bundles CCCL 3.0.2 as
- `references/libraries.md:246` [[edit 1-3, inherited from armA]] **CCCL** -- `/opt/rocm/core-10.1/include/hipccl`, and ROCm 7.2.1 bundles none; newer CCCL levels come from
- `references/libraries.md:255` [[edit 1-3, inherited from armA]] **cuCollections** -- on an empty slot as "taken" loses or duplicates keys (cuCollections: 11 failing
- `references/libraries.md:256` [[edit 1-3, inherited from armA]] **static_set** -- `static_set<int8_t/int16_t>` cases).
- `references/libraries.md:262` [[edit 1-3, inherited from armA]] **cuCollections** -- atomic paths explicitly, because 4-byte tests pass either way. (cuCollections)
- `references/platform-limits.md:90` [[edit 1-3, inherited from armA]] **global_norm, llm.c** -- part it met and breaks here. llm.c's `global_norm.cuh` computes
- `references/platform-limits.md:95` [[edit 1-3, inherited from armA]] **llm.c** -- `__smid()` exceeding `multiProcessorCount` (faults-wavefront.md). (llm.c, gfx942.)
- `references/platform-limits.md:123` [[edit 1-3, inherited from armA]] **layernorm, llm.c** -- Evidence: llm.c (upstream `f1e2ace`) `layernorm_forward` requests `(2 + 8) * C * sizeof(floatX)`
- `references/platform-limits.md:124` [[edit 1-3, inherited from armA]] **GPT-2** -- bytes. At C=768 (GPT-2 124M, what the tests use) that is 30,720 B and runs. At C=1920 in FP32
- `references/platform-limits.md:125` [[edit 1-3, inherited from armA]] **train_gpt2cu** -- (76,800 B), both a direct call and `train_gpt2cu -e d60` abort with `[CUDA ERROR] at file
- `references/platform-limits.md:126` [[edit 1-3, inherited from armA]] **layernorm** -- llmc/layernorm.cuh:453: invalid argument`, the last-error check right after the opt-in, on ROCm
- `references/platform-limits.md:127` [[edit 1-3, inherited from armA]] **llm.c** -- 7.2.1 and 10.1.0. Every model with C >= 1639 in FP32, or C >= 3277 in BF16, is affected. (llm.c,
- `references/strategy-b-torch.md:198` [[edit 4/5, armA..armB]] **pytorch3d** -- - The ROCm release under test is the one the TORCH BUILD targets, not the base image's. A torch extension compiles with the toolchain that matches its torch (`t
- `references/validation.md:23` [[edit 1-3, inherited from armA]] **layernorm, llm.c** -- - Problem size is a coverage axis too. A project's tests usually run its smallest configuration, and code paths that only exist at larger sizes are never execut
- `references/validation.md:24` [[edit 1-3, inherited from armA]] **llm.c** -- - ROCm versions are a coverage axis too. Build and run the suite on the CURRENT ROCm release as well as the one the port was developed against (and the oldest o
- `references/validation.md:25` [[edit 4/5, armA..armB]] **libhipcxx** -- - Validate from a fresh clone, not from the working tree. Before calling a port done, clone (or `git worktree add`) the committed result into a new directory, s
- `evals/evals.json:321` and `:323` [edit 4/5, armA..armB] **cuCollections (by file name)** -- the pr-checklist-port-with-patch-files prompt and expected behaviour name `cmake/hip/cuco_hip.cmake` and `libhipcxx_strong_cas.diff`, which point at a cuCollections port even though the project is not named.

Unnamed but recognisable (no project name in the text):
- `evals/evals.json` review-reduction-kernels-for-mi300x [edit 1]: the code is llm.c's `layernorm_backward`/`global_norm`/`layernorm_forward` patterns ("C is 768 in tests").
- `evals/evals.json` opt-level-dependent-wrong-result-rocm72 [edit 2]: a 10x10 float QR in a solver JIT-compiled with hipRTC (the Warp case).
- `evals/evals.json` torch-extension-validation-matrix [edit 5]: a PyTorch extension built through torch's hipify on rocm7.1/7.2 wheels (the pytorch3d case).
- The commit messages of edits 4 and 5 name llm.c, anthonix/llm.c, cuCollections, ROCm/hipCollections, pytorch3d, NVIDIA Warp and llama.cpp. They are git metadata and do not ship in the skill tree.

Already named on main (so present in the base and in both arms, not part of either treatment):
`references/assess-existing-support.md:4` names karpathy/llm.c and anthonix/llm.c ("missing it
cost one full wasted port"); `references/build-cmake-link.md:506-523` names Warp (AMD Warp
built for IsaacLab on MI300X); `references/strategy-a-cmake.md` and `validation.md` name the
CUDA samples (`NVIDIA/cuda-samples`, `helper_math.h`).
