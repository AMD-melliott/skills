# Feedback — `local-ai-use`

**Reviewer:** Matt Elliott
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy

Review of `SKILL.md`, `reference.md`, `templates/local-ai-rule.md`, and
`scripts/setup_local_ai.py` against a live 11.5.2 stack. The script was run
against scratch directories rather than this workspace, because §2.1 predicted —
and §2.9 then confirmed — that a live run would damage a working configuration.
§4 records what was measured and what was deliberately not run.

**This document holds design feedback, open questions, and research results
only.** Reproduced mechanical defects were submitted separately as a pull
request:

| PR | Covers |
|---|---|
| `fix(local-ai-use): name Debian derivatives, and the two routes outside the /api/v1 pattern` | Prerequisites wording for Ubuntu derivatives (§2.7); the two routes that break the `/api/v1` pattern, for readers extending the rule beyond the three covered modalities (§2.4) |

---

## 1. Confirmed working: the Linux install model is correct

Leading with this because it is the load-bearing assumption of the whole skill
and it holds up — at a version two minor releases beyond what it documents.

```
$ dpkg -l | grep lemonade
ii  lemonade-server  11.5.2~24.04  amd64  Local LLM serving with GPU and NPU acceleration server

$ systemctl list-unit-files | grep lemon
lemond.service    enabled    enabled

$ pgrep -af lemond
2511 /usr/bin/lemond

$ lemonade status
Server is running on port 13305
Version    11.5.2
```

| Claim | Result |
|---|---|
| PPA `ppa:lemonade-team/stable`, package `lemonade-server`, CLI `lemonade` | correct |
| `lemond` auto-starts and is OS-managed | correct — system-level unit, enabled |
| There is **no** `lemonade serve` | correct |
| Capability probe: `lemonade status` prints `Server is running on port 13305` | correct **at 11.5.2**, not just 10.1.0 |
| Default endpoint `http://localhost:13305`, no auth on loopback | correct |

Two things deserve specific credit:

- **Capability-based detection instead of version-string parsing.** Checking
  whether `lemonade status` *behaves* like the modern CLI is why this skill
  still works correctly at 11.5.2 without an edit. The right call, and it paid
  off.
- **Pop!_OS worked via the Ubuntu path.** The package is `11.5.2~24.04` on a
  Pop!_OS 24.04 base. Ubuntu derivatives are fine; the prerequisite wording
  should say so.

---

## 2. What needs improvement

### 2.1 HIGH — No discovery step: the skill overwrites a better configuration with a worse one

The skill's only decision input is CLI flags. It never asks the running server
what is already there. On any host already using Lemonade seriously, that
produces a silent downgrade.

On this box the defaults would write into `AGENTS.md`:

| Modality | Skill default | Already running here | Effect |
|---|---|---|---|
| STT | `Whisper-Tiny` (~0.1 GB) | Whisper via `whispercpp:vulkan` | **downgrade** |
| TTS | `kokoro-v1` | `kokoro-v1` | no change |
| Image | `SD-Turbo` (~5 GB) | not installed | see §2.3 |

`--stt-model` exists, so the user *can* override — but only if they already know
an incumbent exists and that the default is worse. The skill has no step that
looks.

The failure is not "Whisper-Tiny is bad." It is that a skill whose job is
"make future turns use local models" writes its config without reading the state
of the thing it configures. Every user who adopts Lemonade *before* adopting
this skill hits it.

**Suggested fix.** A discovery step between Step 1 and Step 2:

> **Step 1c: see what is already serving.** Before choosing model IDs:
>
> ```bash
> curl -s http://localhost:13305/api/v1/health   # currently loaded models
> curl -s http://localhost:13305/api/v1/models   # full local catalog
> ```
>
> If a model of the right modality is already loaded or pulled, prefer it over
> the default and tell the user which you chose. Fall back to the Lite
> Collection defaults only when the host has nothing for that modality.

Small change, large effect: it turns the skill from "impose defaults" into
"adopt what's here, fill the gaps," which is what its description already
promises. It also resolves most of §2.5 and §2.6 as a side effect.

### 2.2 HIGH — No cascade detection: running in a subdirectory silently creates a second live block (confirmed)

The skill assumes one flat `AGENTS.md` per workspace. Real setups nest:

```
~/git/AGENTS.md                  # workspace root: utility stack, slot model, control plane
  └── /data/uap-demo/AGENTS.md   # explicitly "builds on" the root file
```

Both load, root-first, by directory cascade. The skill does not say which level
is "the workspace," what happens if run at both, or how its marker-fenced block
interacts with a parent block already present.

- Run at `~/git` and again at `/data/uap-demo` — two live blocks. Which model IDs
  win? The deeper file's, presumably, but nothing says so.
- It does **not** detect an existing block in a parent. Confirmed: with
  `/tmp/lau/AGENTS.md` already carrying the block, running from
  `/tmp/lau/nested/deep` printed `created /tmp/lau/nested/deep/AGENTS.md` and
  produced a second file with a duplicate block — no parent lookup, no warning.
  Both load in the cascade, and they drift apart on the next run of either.
- The mirror list offers `CLAUDE.md` / `.cursor/rules/` / `GEMINI.md`. A user
  with two of those now has two copies that drift on the next run.

**Measured against the real cascading `AGENTS.md`.** Running the script over a
throwaway copy of this workspace's actual root file produced two live blocks and
— more importantly — a set of **in-file contradictions with no precedence rule**.
Nothing is overwritten; the skill's block is simply appended last:

| Existing root `AGENTS.md` says | Appended block says |
|---|---|
| L35: Whisper is served by the `transcription:1` slot on a named back-port | transcription goes to `:13305/api/v1/audio/transcriptions` |
| L45–65: the host's slot model, with what may be loaded concurrently | nothing about slots |
| L64: rerank goes to the back-port, not the proxy | n/a |
| L185: the health-check procedure for this host | its own health procedure |

Both blocks load, root-first. An agent reading them has two sets of instructions
for the same operations and no stated way to choose. The skill's block being
*last* is the only tiebreaker, and that is an accident of append order rather
than a design.

This is the part I would most want AMD to weigh in on, because it is not fixable
by the script alone: any workspace with existing local-inference conventions
already has content that this block silently competes with.

**Suggested fix.** Walk up for an existing `amd-skills:local-ai-use` block before
creating a new file. If one is found, update it in place and say so, or require
an explicit `--here` to create a nested override. Print the resolved model IDs
alongside the path — one line that makes the cascade legible. Beyond that, the
rule template could state its own precedence explicitly ("these instructions
apply to image, TTS, and STT only; defer to workspace-specific routing where it
exists") so an appended block declares its scope rather than assuming it.

### 2.3 MEDIUM — The image-generation rule fires unconditionally, with no note on GPU contention **[unverified]**

The rule instructs the agent to call `POST /api/v1/images/generations` for *any*
image request, with no conditions, pulling `SD-Turbo` (~5 GB) on first use.

Worth being precise about what is and isn't a problem here. On 128 GB unified
memory (~120 GB addressable), a quantized chat model and a quantized diffusion
model coresident is plausible — this is not a capacity conflict. Lemonade's slot
model also means loading `image:1` does not evict `llm:1`.

The residual concerns are smaller but real:

- **Concurrent inference, not coresidency.** Two models resident is fine; two
  models *inferring* on one iGPU simultaneously will degrade both. The question
  is scheduling, not capacity.
- **An unprompted ~5 GB pull** at whatever moment the agent decides to generate
  a diagram.
- **The agent decides, not the operator.** The rule is unconditional and loaded
  every turn, so an image request mid-ingest is served without anyone weighing
  the tradeoff.

This is unvalidated in both directions on this hardware — "approach carefully,
plan, and test" rather than "will not work."

**Suggested fix.** One sentence in the rule template, so the tradeoff is visible
at call time rather than buried in setup:

> Image generation and LLM inference share the GPU. Coresident models are
> generally fine on high-memory hosts; **concurrent inference is not**. If a
> long-running job is in flight, ask before generating.

Plus a Prerequisites line noting the first image request triggers a ~5 GB
download, so metered or slow links may prefer an eager pull (§2.5). The §2.1
discovery step would let the rule state what is currently loaded, which is a
better fix than an opt-in flag.

### 2.4 LOW — `reference.md` should name the two routes that break the `/api/v1` pattern

Good news first: the three modalities this skill covers are all correctly
documented. Verified at 11.5.2, `/api/v1/images/generations`,
`/api/v1/audio/speech`, and `/api/v1/audio/transcriptions` all resolve, and
`/api/v1/*` and `/v1/*` are aliases for them — so the skill's internal
inconsistency (both spellings appear across `SKILL.md` and `reference.md`) is
harmless and needs no fix.

Two routes do break the pattern, and matter only because `reference.md` invites
extension into other modalities:

| Route | Reality |
|---|---|
| `messages` (Anthropic) | `/v1/messages` only — `/api/v1/messages` 404s |
| `rerank` | proxy serves `/api/v1/reranking`; `/api/v1/rerank` 404s, though the per-model back-port serves `/v1/rerank` |

*Fixed in the PR* — `reference.md` gains an "if you extend the rule beyond these
three modalities" note listing both exceptions, and states explicitly that the
three covered modalities are alias-safe so the mixed spellings need no change.
The sibling `local-ai-app-integration` review covers both routes in more depth.

### 2.4b MEDIUM — The slow-image-generation remedy assumes the only cause is a missing backend

The troubleshooting table has exactly one performance row:

| Symptom | Cause | Recovery |
|---|---|---|
| Image generation is slow on CPU (~4–5 min) | sd-cpp on CPU backend | `lemonade backends install sd-cpp:rocm` |

Right symptom, right command — `system-info` confirms `sd-cpp:rocm` is
`installable` on `amd_gpu` for gfx1151, so the advice is sound as far as it
goes. But it names one cause for a symptom that has several, and the others all
look identical:

> "Failure is SILENT and looks like success. With the HIP libs unreachable,
> `libggml-hip.so` simply never loads and llama.cpp falls back to CPU — exit
> code 0, sensible-looking output, **16x slower prefill**." And:
> "**`rocminfo` succeeding does NOT mean HIP works**."

A user who runs the suggested install, sees it report success, and is still slow
has been left with nowhere to go — the table's one row is spent. Other causes
with the same presentation: rootless containers on `runc` instead of `crun` (so
`/dev/kfd` maps to `nobody`), a container ROCm userspace mismatched to the host
driver, known-bad firmware, or a kernel below the gfx1151 minimum.

**Suggested fix.** Split the row so the second half has somewhere to go:

| Symptom | Cause | Recovery |
|---|---|---|
| Image generation is slow on CPU (~4–5 min) | `sd-cpp` running on the CPU backend | `lemonade backends install sd-cpp:rocm` |
| Still slow after installing the GPU backend | The backend is installed but not actually engaged — the runtime fell back to CPU silently | An `installed` state in `system-info` and a successful `rocminfo` both still permit a silent CPU fallback. Check real GPU utilisation (`gpu_busy_percent`) during a request, and confirm the host's GPU driver stack rather than re-installing the backend |

This is the local-ai-use-sized slice of a larger gap: none of the three skills
mentions any host-layer prerequisite — no kernel or firmware minimums, no
`/dev/kfd` or `/dev/dri`, no `crun`, no `HSA_OVERRIDE_GFX_VERSION`, no
unified-memory sizing. The full argument, and a proposal for where that content
should actually live, is in the `local-ai-app-integration` review (§2.5, §3.3);
it belongs there because that skill ships onto machines its author never sees.
For this skill, the one troubleshooting row above is the whole ask.

### 2.5 MEDIUM — Nothing distinguishes "installed" from "pulled" from "loaded"

The verification checklist ends at server running + rule block present + a
follow-up turn POSTing locally. A user can pass all three and still hit a
four-minute first image generation, or a stalled pull.

The skill *knows* this — the troubleshooting table has both the slow-CPU row and
the excellent stalled-pull row (`models_dir` / `free_bytes` via
`/api/v1/system-info`, and reading the server log for the real error). That
knowledge never reaches the happy path.

**Suggested fix.** One optional warm-up step: after writing the rule, offer to
pull the selected models immediately, and report free disk against the ~8 GB
requirement *before* starting. Keep lazy pull as the default — it is the right
call — but make eager pull one flag away, because "first use" is the worst
possible moment to discover a 5 GB download.

### 2.6 MEDIUM — Version currency **[unverified]**

The skill targets "v10.1.0 or newer"; live is 11.5.2 and the core paths work.
But model IDs are asserted without a tested-against version — `SD-Turbo`,
`kokoro-v1`, `Whisper-Tiny`, and the alternates in the `reference.md` picker are
hardcoded strings, and catalogs move.

The sibling `local-ai-app-integration` already teaches this discipline
(`server_models.json` can be stale; `GET /api/v1/models` is the only authority).
Same rule should apply here.

**Suggested fix.** State a tested-against version range, and add a line to the
model picker: verify IDs against `GET /api/v1/models` before writing them into
the rule — which the §2.1 discovery step would do anyway.

### 2.7 LOW — Prerequisites should say "Ubuntu/Debian **and derivatives**"

Pop!_OS 24.04 works fine via the documented PPA path — this whole review ran on
it. A user on Mint, Pop!_OS, or elementary reading "Ubuntu/Debian x64" may
assume they are unsupported. *Fixed in the PR.*

### 2.8 LOW — `--no-install` is under-documented

It appears once, in Prerequisites. It does not appear in the opinionated path,
the troubleshooting table, or the Step 1 flow — despite being the correct flag
for a common case: a managed or shared machine where the agent should not run
`sudo apt-get install`. Worth a row in Step 1.

### 2.9 MEDIUM — A bare re-run silently reverts customisation (confirmed)

"Re-running it on a fully configured workspace is a no-op apart from a
healthcheck" holds only when the first run used no flags. Confirmed:

| step | command | STT model written |
|---|---|---|
| 1 | `setup_local_ai.py --no-install` | `Whisper-Tiny` |
| 2 | `--no-install --stt-model Whisper-Large-v3-Turbo` | `Whisper-Large-v3-Turbo` |
| 3 | `--no-install` *(bare)* | **`Whisper-Tiny`** — reverted |

No warning, no diff. This compounds §2.1: the script neither remembers prior
choices nor discovers what is serving, so the *safe-looking* action — re-running
an idempotent setup script — is the one that downgrades the configuration.

**Suggested fix.** Persist the resolved model IDs and reuse them when flags are
absent, or read the existing block's values and print
`keeping Whisper-Large-v3-Turbo (pass --stt-model to change)`.

---

## 3. What works well

### 3.1 Lazy model pull

Not downloading ~8 GB at setup for modalities the user may never touch is the
right default, and the skill says why. The decision most likely to be
second-guessed, and it is correct.

### 3.2 Marker-fenced idempotent block

```
<!-- BEGIN amd-skills:local-ai-use -->
<!-- END amd-skills:local-ai-use -->
```

Replace-in-place rather than append is the difference between a skill that can
be re-run and one that accretes garbage. Telling hand-editors to preserve the
exact markers is a nice touch.

### 3.3 The anti-shortcut instruction

"**Always run this script first — even if Lemonade is already installed and the
server is already running**" plus the matching checklist line ("generating an
image alone does not complete the skill") anticipates the specific way an agent
would cut this skill short. Good instinct: it defends against the agent, not
just the environment.

### 3.4 The old-CLI shadowing section

The uninstall matrix by install channel, "never try to drive or auto-remove it
for the user," and the repeated "never `pip install lemonade-sdk`, that is a
separate older release line." Hard-won and well placed, and the capability-based
detection behind it is what makes it robust.

### 3.5 The stalled-pull troubleshooting row

> `lemonade pull` keeps printing `Progress: NN%` but never finishes … the write
> error may surface only in the server log while the console keeps showing
> progress

Correct root cause, the right diagnostic, and a pointer to where the real error
hides. Nobody writes this without having lost an afternoon to it.

### 3.6 Explicit non-silent-fallback policy

"Only fall back to a cloud API after one local attempt has failed *and* the user
has been told" — correct for a skill whose premise is cost predictability.
Silent fallback would make it worse than useless, since the user would believe
they had stopped paying.

### 3.7 Honest scoping

"This skill does not redirect chat tokens; it only redirects the multimodal
calls" is stated twice. Given the description leads with saving money, being
upfront that the largest token cost is untouched is the right kind of honesty.

---

## 4. Testing performed

Scratch-first throughout: §2.1 and §2.3 predicted a live run would damage a
working configuration, and §2.9 confirmed it, so nothing ran against this
workspace's real `AGENTS.md`.

| # | Test | Status | Settles |
|---|---|---|---|
| T1 | `setup_local_ai.py` clean-slate run | **done**; works, correctly detects the system `lemond`, reports each step, one marker block | general |
| T2 | Re-run idempotence with and without flags | **done**; block does not duplicate, but a bare re-run reverts customisation | §2.9 |
| T3 | Cascade — run from a nested directory under an existing block | **done**; parent not detected, second block created | §2.2 |
| T4 | Merge against a copy of the real cascading `AGENTS.md`; diff the result | **done**; two live blocks and four in-file contradictions with no precedence rule | §2.1, §2.2 |
| T5 | `sd-cpp:rocm` on gfx1151 — install and measure | **partial**; `system-info` reports it `installable` on `amd_gpu`, so the command is right and offered. Performance unmeasured | §2.4b |
| T6 | Endpoint/namespace sweep | **done**; the three covered modalities are documented correctly; `messages` and `reranking` are the two exceptions | §2.4 |

**T5 is the only remaining gap, and it is bounded.** Completing it needs a
backend install plus a ~5 GB model download, and it would measure *this
hardware's* image-generation throughput — a number that says little about the
skill, since the troubleshooting row it tests (§2.4b) is about a class of silent
CPU fallback rather than about any particular speed. The read-only half already
confirms the skill offers the right command on the right hardware. What it
cannot confirm is the §2.4b claim that a successful install can still leave you
on CPU; that one comes from host-level tuning work on this machine rather than
from Lemonade, and it is why the suggested fix is a second troubleshooting row
rather than a correction to the first.

Nothing further is planned. The two findings that matter most — the silent
reversion (§2.9) and the cascade collision (§2.2) — are both confirmed by
direct execution rather than inferred from reading the script.

---

## 5. Summary

The install-and-detect half is **verified working** on real hardware at a
version beyond what it documents, and capability-based probing is the design
decision that earned that. The `AGENTS.md` mechanism is sound and the
troubleshooting content is unusually good.

The weakness is one-directional configuration: **the skill writes but never
reads.** No discovery of what is already serving (§2.1), no model for a nested
cascade (§2.2), no note that image generation shares the GPU with LLM inference
(§2.3), and a bare re-run that silently reverts customisation (§2.9). All four
share a root cause, and largely a fix — a single discovery step against
`GET /api/v1/health` and `/api/v1/models` before deciding anything, plus reading
the existing block's values instead of re-deriving them from flags. That also
resolves most of §2.5 and §2.6.

That one addition takes this from "good for a fresh machine" to "safe on a
machine that already matters." Both confirmed failure modes only appear on the
second kind of machine, which is exactly the kind least likely to be used for
testing.
