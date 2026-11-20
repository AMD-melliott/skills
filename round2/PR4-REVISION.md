# PR 4 revision: report on the existing-port verdict change

Everything here is local. Nothing was pushed: the `origin` push URL is still `DISABLED-no-push`. There were no GPU,
container or `claude -p` runs, and nothing outward-facing was done. Only the three named branches were created and no
other branch was modified. 2c62f93f was neither amended nor rebased. Each branch has its own new worktree under
`round2/arms/`; the main checkout was not touched.

## Commits

| branch | commit | tree | parent | worktree |
|---|---|---|---|---|
| `round2/armB4r` | `b7c7b1e240058c18a6ef19f5b9aa057e970a265e` | `2873342ece9d7a1a4f497b1291e407f54e86b228` | `c7628017` (round2/armA) | `round2/arms/armB4r` |
| `round2/armB4r-di` | `79b94a33794c35f65194102ef18ce1a05f3e42d0` | `ea3eb02bff5b7c2c80805fae848b5604458b31b0` | `b7c7b1e2` (armB4r) | `round2/arms/armB4r-di` |
| `pr4-rev-fork` | `6ce7179a268ba66124e858cd90c8cd5083b4c5f3` | `32ea6a4f09f0d6963894725178b23512ed2ba4bc` | `2c62f93f` (fork/moat-pr/existing-port-verdict) | `round2/arms/pr4-rev-fork` |

- **armB4r** is ONE commit on armA: the revised PR 4. I cherry-picked 025e7519, then amended it with the revision. The
  verdict paragraph ("Running the grep is not the check...") and the regression-guard eval are therefore byte-identical
  to 025e7519. Diff against armA: SKILL.md +19, evals.json +53 (three evals), assess-existing-support.md +2. The
  generated SKILL index did not change (`gen_skill_index.py`: "index and contents are current").
- **armB4r-di** is the TEST-ONLY commit on top of armB4r. It changes the assess-existing-support.md sentence, using
  e8dec6f5's exact substitution, and the prompts and expected text of the two new evals. SKILL.md and the llm.c
  regression-guard eval are unchanged, because neither names a test project.
- **pr4-rev-fork** is one NEW commit on top of 2c62f93f, in the old file layout. Its new SKILL.md paragraph and its
  assess-existing-support.md paragraph are byte-identical to armB4r's. The two new evals are the same objects, placed
  directly after `existing-amd-fork-linked-in-readme`, as on armB4r.

## Commit message (armB4r)

```
cuda-to-rocm: act on the existing-port check; build on AMD's own port

SKILL.md told the agent to check for existing AMD support but not to act on a hit, and the worked example (llm.c linking an AMD fork) lives only in assess-existing-support.md, which an agent working from the router may never open.

Evidence: in an llm.c port the agent's first command was the grep, which printed README:206 linking anthonix/llm.c. The fork was never mentioned again: no PR or web search, no authoritative-vs-community judgement. In two independent cuCollections ports the agent found ROCm/hipCollections, recorded it as AMD's own, and built a parallel port anyway. In pytorch3d, NVIDIA Warp and llama.cpp ports the same check led to building on the existing AMD work, which is the intended behaviour. A first version of this change told the agent to stop and ask before writing port code; in four blind ports (two cuCollections, two nccl-tests) every run wrote a good verdict and none started a parallel port, but all four ended the run with a question and delivered nothing. One recommended the parallel port anyway, reading "keep the CUDA build unchanged" as something only a port of this repo could satisfy.

Adds a recorded verdict before any port code. When the verdict names an authoritative AMD port, the agent states the verdict and its path first and then takes that path in the same run instead of ending on a question: contribute what the AMD port lacks against current upstream in a local clone of it, built and tested on the GPU, or, if the gap is too large for one run, validate the AMD port as it is and write the gap up. A constraint like "keep the CUDA build unchanged" limits how the requested repo may change and is met by leaving it unchanged; porting that repo anyway is for a stated need the AMD port cannot meet even with contributions, such as one source tree for both vendors.

Three evals. One (linked fork in README) is a regression guard: the unmodified skill passes it too. Two cover the new behaviour: an authoritative AMD port that lags upstream under a "keep the CUDA build unchanged" request (proceed on the contribute or validate path, no question, no parallel port), and an explicit single-source-tree need (port this repo, say why, use the AMD port as the reference).

Test Plan:

    MOAT_LOCAL_TOOLS=1 uv run --python 3.13 python utils/check.py skills harness-adapters jargon

Authored with Claude.
```

(In the commit itself the Test Plan command is in a triple-backtick fence. It is indented here only so this block
renders.) There is no Co-Authored-By trailer.

**I changed the title.** It was "...; ask before a parallel port", which now says the opposite of the rule. If you want
the old title kept, revert this one line. The fork commit is a delta on top of 2c62f93f, so it has its own title:
"cuda-to-rocm: take the existing-port path instead of stopping to ask". Its body:

- opens with one sentence saying it revises the previous commit's stop-and-ask rule;
- then repeats the armB4r body, with "index" in place of "router" (that tree still has the hand-written index);
- uses that tree's Test Plan, `python3 utils/check.py --fast`, placed after "Authored with Claude." as in 2c62f93f.

## Before / after

### SKILL.md, "Before porting" (the verdict paragraph above it is unchanged)

Before (025e7519 and 2c62f93f):

```
**If the verdict names an authoritative AMD port and you were asked to port, stop and ask
before writing port code.** Put three options to the user: contribute what the AMD port lacks
to it; validate the AMD port as it is; or port current upstream anyway, saying why the AMD
port cannot serve. A gap in the AMD port (it lags upstream, it lacks a feature) is the thing
to contribute, not a reason for a parallel port. With no one to ask, take one of the first
two and write the gap up.
```

After (armB4r, armB4r-di and pr4-rev-fork; identical in all three):

```
**If the verdict names an authoritative AMD port and you were asked to port, do not stop to
ask** (unless the user is present and said to check in). Put the verdict and your path where
the user will see it first, then take that path in the same run; the user can redirect.
Default: clone the AMD port inside the working directory, commit what it lacks against
current upstream (features, upstream fixes), and build and test it on the GPU; if that gap is
too large for one run, validate the port as it is. Either way, say where the work is and what
gap is left. "Keep the CUDA build unchanged" limits how THIS repo may change, and leaving it
unchanged satisfies it. Port this repo anyway only for a need the AMD port cannot meet even
with contributions (one source tree for both vendors), say so in the verdict, and still use
the AMD port as the reference for fixes it already found.
```

The new paragraph is 10 lines; the old one was 6. I could not make it shorter and still cover everything brief items 2
to 4 require:

- no asking by default, with the brief check-in exception;
- contribute by default, with validating the AMD port as the fallback;
- the deliverable: a clone inside the working directory, with commits, built and tested on the GPU, and a summary of
  where the work is and what is left;
- how to read "keep the CUDA build unchanged", and the single-source-tree exception.

### references/assess-existing-support.md

Before (025e7519 and 2c62f93f):

> Finding the AMD effort is not where this goes wrong; acting on it is. Two independent ports of NVIDIA cuCollections both found ROCm/hipCollections (part of ROCm-DS), recorded it as AMD's own, and built a parallel port anyway, reasoning that it lagged upstream (no HyperLogLog, no `dynamic_map`). That lag was the differentiator to contribute. So when the classification below lands on "skip" or "validate and improve" and the request was "port it", stop and put the choice to the user rather than resolving it by porting.

After (armB4r and pr4-rev-fork):

> Finding the AMD effort is not where this goes wrong; acting on it is. Two independent ports of NVIDIA cuCollections both found ROCm/hipCollections (part of ROCm-DS), recorded it as AMD's own, and built a parallel port anyway, reasoning that it lagged upstream (no HyperLogLog, no `dynamic_map`). That lag was the differentiator to contribute. Told to stop and ask instead, four later runs all wrote that verdict and then ended on the question, delivering nothing. So when the classification below lands on "skip" or "validate and improve" and the request was "port it", state the verdict and take that path in the same run: contribute the gap to a local clone of the AMD port and test it on the GPU, or validate the port as it is and write the gap up. A request to leave this repo's CUDA build unchanged is met by leaving the repo unchanged; it is not a reason for a second port.

After (armB4r-di):

> Finding the AMD effort is not where this goes wrong; acting on it is. Two independent ports of one CUDA library both found AMD's own, separately named port of it, recorded it as AMD's own, and built a parallel port anyway, reasoning that it lagged upstream (it lacked two data structures upstream had added since). That lag was the differentiator to contribute. Told to stop and ask instead, four later runs all wrote that verdict and then ended on the question, delivering nothing. So when the classification below lands on "skip" or "validate and improve" and the request was "port it", state the verdict and take that path in the same run: contribute the gap to a local clone of the AMD port and test it on the GPU, or validate the port as it is and write the gap up. A request to leave this repo's CUDA build unchanged is met by leaving the repo unchanged; it is not a reason for a second port.

### evals.json

`existing-amd-fork-linked-in-readme`, the regression guard, is kept unchanged. It was the only PR 4 eval before this
revision, so "update the eval(s)" meant adding two new evals for the new behaviour. Both are inserted directly after
the guard:

```json
{
  "id": "authoritative-amd-port-proceed-without-asking",
  "skill_should_trigger": true,
  "prompt": "Port this CUDA concurrent hash-table library (NVIDIA cuCollections) to ROCm/HIP so it builds and its tests pass on this MI300X; keep the CUDA build unchanged. Your existing-support check found ROCm/hipCollections (https://github.com/ROCm/hipCollections), AMD's own HIP port, part of ROCm-DS: active, tested on MI300X, HIP-only. It lags upstream: no HyperLogLog, no `dynamic_map`, and some recent upstream fixes. Write plan.md with your verdict and exactly what you will do in this run, then stop. Don't clone or build anything.",
  "expected_behavior": [
    "Record the verdict first: hipCollections found, with its URL, judged authoritative (AMD-official), and what it lacks against current upstream",
    "Commit to a path in this run without waiting for an answer: contribute the gap (the missing data structures and upstream fixes) to a local clone of hipCollections and build and test it on the MI300X, or, if the gap is too large, validate hipCollections as it is and write the gap up",
    "Read 'keep the CUDA build unchanged' as a limit on how this repo may change, satisfied by leaving it unchanged, not as a reason for a second port"
  ],
  "unexpected_behavior": [
    "End with a question or a list of options for the user to choose from instead of a chosen path",
    "Plan a parallel HIP port of this repo, citing the CUDA-build constraint or the AMD port's lag as the reason"
  ],
  "files_exist": ["plan.md"]
}
{
  "id": "authoritative-amd-port-single-tree-need",
  "skill_should_trigger": true,
  "prompt": "Port NVIDIA nccl-tests to ROCm/HIP. We need ONE source tree that builds for both NVIDIA and AMD from the same commits, so our CI can compare the two vendors line by line. Your existing-support check found AMD's rccl-tests (now in ROCm/rocm-systems under projects/rccl-tests): AMD-official, active, HIP-only, at nccl-tests 2.19.6 while upstream is at 2.21.1. Write plan.md with your verdict and exactly what you will do in this run, then stop. Don't clone or build anything.",
  "expected_behavior": [
    "Record the verdict: the AMD port, with where it lives, judged authoritative",
    "State that the single-source-tree requirement is a need the AMD port cannot meet even with contributions, and so port this repo, saying so in the verdict",
    "Use the AMD port as the reference for fixes and ROCm-specific handling it already found rather than rediscovering them",
    "Proceed with the plan in this run rather than asking the user to choose"
  ],
  "unexpected_behavior": [
    "Refuse to port this repo, or only validate the AMD port, despite the stated single-tree need",
    "Ignore the AMD port entirely"
  ],
  "files_exist": ["plan.md"]
}
```

In -di:

- The first prompt becomes "Port this CUDA concurrent hash-table library to ROCm/HIP ... Your existing-support check
  found AMD's own, separately named HIP port of this library: AMD-official, active, tested on MI300X, HIP-only. It lags
  upstream: it lacks two data structures upstream has added since, and some recent upstream fixes. ...". In its
  expected text, "hipCollections" becomes "the AMD port".
- The second prompt becomes "Port this CUDA collective-communication benchmark suite to ROCm/HIP. ... found AMD's own,
  separately named HIP port of the suite: AMD-official, active, HIP-only, two upstream minor versions behind. ...".

The file is still serialised with `json.dumps(indent=2)`. Before editing, I checked that this reproduces the existing
file byte for byte. The diff contains only additions.

## Gates

Command: `CODEX_HOME=$(mktemp -d) MOAT_LOCAL_TOOLS=1 uv run --python 3.13 python utils/check.py skills harness-adapters jargon`

armB4r:

```
moat: MOAT_LOCAL_TOOLS is set, so this checkout's own tooling is deciding, not the trunk's (origin/main)
skills: ok
harness-adapters: ok
jargon: ok
exit 0
```

armB4r-di:

```
moat: MOAT_LOCAL_TOOLS is set, so this checkout's own tooling is deciding, not the trunk's (origin/main)
skills: ok
harness-adapters: ok
jargon: ok
exit 0
```

pr4-rev-fork: the older tree has the same three gates, and they pass with the same command:

```
skills: ok
harness-adapters: ok
jargon: ok
exit 0
```

I also ran `check.py --fast` on pr4-rev-fork, the command its own Test Plan names, with `CODEX_HOME` set the same way.
It exits 1 with five failures:

```
5 gate(s) failed
gh-guard: gh guard is not installed at /home/melliott/.local/bin/gh (python3 utils/install_hooks.py)
code: pyflakes not installed (pip install pyflakes); cannot check code
schema: jsonschema not installed; cannot validate status files
readme: README table is stale (run utils/gen_readme.py)
optout: GPUMD (brucefan1983/GPUMD): its owner opted out but the project is still live at stage review-passed -- python3 utils/optout.py record retires it
(every other gate ok; published: VACUOUS)
```

The edit does not cause these. **The unmodified 2c62f93f fails the same five.** I checked that in a temporary detached
worktree, since removed. The failures come from this host (the gh guard, pyflakes and jsonschema are not installed) or
from that tree's own data (the README table is stale, and the GPUMD opt-out is still live). Without the `CODEX_HOME`
override, the base also fails `harness-adapters`, because of the revoked codex login described in ARMS.md.

## Not done / notes

- **Other project names are still in -di.** cuCollections still appears in `references/libraries.md` and
  `references/faults-memory-streams.md`; both come from armA's edit 1, not PR 4. ROCm-DS appears in main's own text:
  libraries.md, windows.md, the generated SKILL index, and the "ROCm-DS-style" classification line in
  assess-existing-support.md. The brief limits -di to the PR 4 text and evals, and e8dec6f5 left these same lines.
  If a blind cuCollections run must see none of these names, those lines need the same treatment. No nccl-tests or
  rccl-tests names remain anywhere in the -di skill.
- **Nothing has been measured.** As the brief says, I ran no evals and no blind runs. It is unknown whether the new
  paragraph gets unattended runs from the verdict into a clone, commits and a GPU test.
- **The SKILL.md paragraph is 10 lines, not about 6** (see the note under SKILL.md above).
- **The fork branch has no extra conflicts.** Its SKILL.md still has the "Cheapest high-signal check first: grep ..."
  sentence, so in that tree "Running the grep is not the check" refers to a grep SKILL.md actually describes.
- **The worktrees are left in place for review:** `round2/arms/armB4r`, `round2/arms/armB4r-di` and
  `round2/arms/pr4-rev-fork`.
