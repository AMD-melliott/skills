# Feedback — `local-ai-use`

**Reviewer:** Matt Elliott
**Date:** 2026-08-11 (initial pass — desk review + live environment probe; script execution pending)
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy

> **Status of this document.** §1 reports a live environment probe that
> **confirms** the skill's Linux assumptions. §2 is a desk review of `SKILL.md`,
> `reference.md`, `templates/local-ai-rule.md`, and `scripts/setup_local_ai.py`.
> Items marked **[unverified]** are hypotheses the test plan in §4 will settle —
> I have not yet run `setup_local_ai.py` on this box, deliberately, because §2.1
> predicts it would damage a working configuration.

---

## 1. Confirmed working: the Linux install model is correct

Leading with this because it is the load-bearing assumption of the entire skill
and it holds up — at a version two minor releases beyond what the skill
documents.

Probed on 2026-08-11:

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

Every Linux-specific claim in Step 1 checks out:

| Claim | Result |
|---|---|
| PPA `ppa:lemonade-team/stable`, package `lemonade-server`, CLI `lemonade` | ✅ correct |
| `lemond` auto-starts and is OS-managed | ✅ correct — system-level unit, enabled |
| There is **no** `lemonade serve` in modern Lemonade | ✅ correct |
| Capability probe: `lemonade status` prints `Server is running on port 13305` | ✅ correct **at 11.5.2**, not just 10.1.0 |
| Default endpoint `http://localhost:13305`, no auth on loopback | ✅ correct |

Two things deserve specific credit:

- **Capability-based version detection instead of version-string parsing.**
  Checking whether `lemonade status` *behaves* like the modern CLI, rather than
  parsing a version, is why this skill still works correctly at 11.5.2 without
  an edit. That is the right call and it paid off.
- **Pop!_OS worked via the Ubuntu path.** The package is `11.5.2~24.04` on a
  Pop!_OS 24.04 base. The skill says "Ubuntu/Debian x64"; Ubuntu derivatives are
  in fact fine. Worth widening the prerequisite wording.

---

## 2. What needs improvement

### 2.1 HIGH — No discovery step: the skill overwrites a better configuration with a worse one

The skill's only decision input is CLI flags. It never asks the running server
what is already there. On any host that is already using Lemonade seriously,
that produces a silent downgrade.

Concretely, on this box the skill's defaults would write into `AGENTS.md`:

| Modality | Skill default | Already running here | Effect |
|---|---|---|---|
| STT | `Whisper-Tiny` (~0.1 GB) | Whisper via `whispercpp:vulkan` | **downgrade** |
| TTS | `kokoro-v1` | `kokoro-v1` | no change |
| Image | `SD-Turbo` (~5 GB) | *deliberately not installed* | see §2.2 |

`--stt-model` exists, so the user *can* override — but the user has to already
know an incumbent exists and that the default is worse. The skill has no step
that looks.

**Why this generalises:** the failure is not "Whisper-Tiny is bad." It is that
a skill whose stated job is "make future turns use local models" writes its
config without reading the state of the thing it is configuring. Every user who
adopts Lemonade *before* adopting this skill hits it.

**Suggested fix.** Add a discovery step between Step 1 and Step 2:

> **Step 1c: see what is already serving.** Before choosing model IDs, check what
> the host already has:
>
> ```bash
> curl -s http://localhost:13305/api/v1/health   # currently loaded models
> curl -s http://localhost:13305/api/v1/models   # full local catalog
> ```
>
> If a model of the right modality is already loaded or already pulled, prefer it
> over the default and tell the user which you chose. Only fall back to the Lite
> Collection defaults when the host has nothing for that modality.

This is a small change with a large effect: it turns the skill from
"impose defaults" into "adopt what's here, fill the gaps," which is what its own
description ("route the agent's tool calls to a local model") actually promises.

### 2.2 MEDIUM — The image-generation rule fires unconditionally, with no note on GPU contention **[unverified]**

> **Revised 2026-08-11.** An earlier draft of this section claimed the rule
> could *evict* a running LLM and rated it HIGH. That was wrong on two counts
> and is corrected below. The residual concern is real but smaller.

The installed rule instructs the agent to call
`POST /api/v1/images/generations` for *any* image request, with no conditions,
and to pull `SD-Turbo` (~5 GB) on first use.

**What the earlier draft got wrong:**

1. **Capacity is not the constraint on this class of hardware.** Strix Halo has
   128 GB unified memory, of which ~120 GB is addressable for model weights. A
   quantized chat model and a quantized diffusion model comfortably coresident
   is plausible, not exotic. Framing this as a memory conflict was wrong.
2. **The arbiter is not in this code path.** My control plane's `GpuArbiter`
   swaps the iGPU between `llm` and `img` for **ComfyUI**, which runs as a
   separate podman container that takes the GPU by design. `local-ai-use` routes
   to Lemonade's own `image:1` slot via `sd-cpp` — a different mechanism
   entirely, and one that per Lemonade's slot model does **not** evict other
   slots. I conflated the two.

**What the residual concern actually is** — three smaller things, none fatal:

- **Concurrent inference, not coresidency.** Two models resident is fine; two
  models *inferring* on one iGPU at the same time will degrade both. The
  question is scheduling, not capacity.
- **An unprompted ~5 GB pull.** The first image request downloads SD-Turbo at
  whatever moment the agent decides to generate a diagram.
- **The agent decides, not the operator.** The rule is unconditional and loaded
  every turn, so an image request mid-ingest is generated without anyone
  weighing the tradeoff.

Worth stating plainly: **this is unvalidated in both directions.** My own
planning docs defer local image generation as out of scope, but that was a
scoping decision, not a measured result. "Approach carefully, plan, and test" is
the honest characterisation — not "will not work."

**Revised suggestion**, much lighter than the original:

Add one sentence to the rule template so the tradeoff is visible at call time
rather than buried in setup:

> Image generation and LLM inference share the GPU. Coresident models are
> generally fine on high-memory hosts; **concurrent inference is not**. If a
> long-running job is in flight, ask before generating.

And one line to Prerequisites noting that the first image request triggers a
~5 GB download, so hosts on metered or slow links may prefer an eager pull (see
§2.5).

I no longer think image generation needs to be opt-in by default. The
`GET /api/v1/health` discovery step from §2.1 would let the rule state what is
currently loaded, which is a better fix than a flag.

### 2.3 HIGH — "Run once per workspace" is undefined for an `AGENTS.md` cascade **[unverified]**

The skill assumes one flat `AGENTS.md` per workspace. Real setups nest. Here:

```
~/git/AGENTS.md              # workspace root: utility stack, slot model, control plane
  └── /data/uap-demo/AGENTS.md   # explicitly "builds on" the root file
```

Both are loaded, root-first, by directory cascade. The skill does not say which
level is "the workspace," what happens if it is run at both, or how its
marker-fenced block interacts with a parent block that is already present.

Three concrete unanswered questions:

- Run at `~/git` and again at `/data/uap-demo` — two blocks, both live. Which
  model IDs win? The later file's, presumably, but the skill never says.
- Does the script detect an existing `amd-skills:local-ai-use` block in a
  *parent* `AGENTS.md`? (Reading the script, it looks for markers in the target
  file only. **[unverified]** — needs a run to confirm.)
- The mirror list mentions `CLAUDE.md` / `.cursor/rules/` / `GEMINI.md` for
  agents with a different convention. If a user has both `AGENTS.md` and
  `CLAUDE.md`, they now have two copies that drift on the next run.

**Suggested fix.** State the rule explicitly: the block goes in the nearest
`AGENTS.md` at or above the working directory; if one already exists in a parent,
update that one rather than adding a second. And have the script say which file
it wrote, with the resolved model IDs — one line of output that makes the
cascade legible.

### 2.4 MEDIUM — Back-ports are invisible, so the rule is incomplete for some modalities

The rule template points every call at `http://localhost:13305/api/v1/...`. But
Lemonade runs per-slot back-ends on their own ports, and not everything is
proxied. On this box right now:

```
:8001  Qwen3-Embedding-0.6B-Q8_0        embedding:1
:8002  bge-reranker-v2-m3-Q8_0          reranking:1
:8003  Qwen2.5-VL-7B-Instruct-Q4_K_M    llm:1
```

`/v1/rerank` in particular lives on the back-port, **not** on the `:13305`
proxy, and the port is assigned dynamically — it has to be discovered from
`/api/v1/health` rather than hardcoded.

This does not break the three modalities the skill covers today (images, TTS,
STT are proxied). It matters because:

- The skill's own `reference.md` invites extension, and the next modality a user
  reaches for is embeddings or rerank.
- A reader comes away believing `:13305/api/v1` is the whole surface, which is
  not true.

**Suggested fix.** One paragraph in `reference.md`: Lemonade serves some
endpoints from per-slot back-ports; discover them from `GET /api/v1/health`
(`backend_url` per loaded model) rather than assuming `:13305`. Note explicitly
that `/v1/rerank` is one of them.

### 2.5 MEDIUM — Nothing distinguishes "installed" from "pulled" from "loaded"

The verification checklist ends at "the server is running" plus "the rule block
exists" plus "a follow-up turn POSTs to the local endpoint." A user can pass all
three and still have a first image request that takes four minutes, or a pull
that stalls.

The skill *knows* this — the troubleshooting table has both the slow-CPU row and
the excellent stalled-pull row (`models_dir` / `model_storage.free_bytes` via
`/api/v1/system-info`, and reading `lemonade-server.log` for the real error).
That knowledge just never reaches the happy path.

**Suggested fix.** Add one optional warm-up step: after writing the rule, offer
to pull the selected models immediately rather than lazily, and report free disk
against the ~8 GB requirement *before* starting. Keep lazy pull as the default —
it is the right call — but make eager pull one flag away, because "first use" is
usually the worst possible moment to discover a 5 GB download and a
four-minute CPU generation.

### 2.6 MEDIUM — Version currency **[unverified]**

The skill targets "v10.1.0 or newer"; live is 11.5.2 and the core paths work.
But the model IDs are asserted without a tested-against version — `SD-Turbo`,
`kokoro-v1`, `Whisper-Tiny`, and the alternates (`SDXL-Turbo`,
`Flux-2-Klein-4B`, `Whisper-Large-v3-Turbo`) are hardcoded strings in the
`reference.md` picker, and the catalog can move.

The skill already teaches this lesson elsewhere in the family
(`local-ai-app-integration` correctly says `server_models.json` can be stale and
`GET /api/v1/models` is the only authority). Same rule should apply here.

**Suggested fix.** State a tested-against version range, and add a line to the
model picker: verify IDs against `GET /api/v1/models` before writing them into
the rule — which the discovery step in §2.1 would do anyway.

### 2.7 LOW — Prerequisites should say "Ubuntu/Debian **and derivatives**"

Pop!_OS 24.04 works fine via the documented PPA path. A user on Mint, Pop!_OS,
or elementary reading "Ubuntu/Debian x64" may assume they are unsupported. One
word fixes it.

### 2.8 LOW — The `--no-install` flag is under-documented

It appears once, in Prerequisites, as "Pass `--no-install` if the user wants to
install it themselves instead." It does not appear in the opinionated path, the
troubleshooting table, or the Step 1 flow — even though it is the correct flag
for a fairly common case: a managed or shared machine where the agent should not
be running `sudo apt-get install`. Worth a row in Step 1.

### 2.9 LOW — Skill claims idempotence; worth stating what "no-op" excludes

"Re-running it on a fully configured workspace is a no-op apart from a
healthcheck" is a strong claim. If a re-run also re-resolves model IDs from
flags, then a re-run *without* the flags used the first time would silently
revert customisation back to defaults. **[unverified]** — but if true, it should
be called out; if false, saying so explicitly would be reassuring.

---

## 3. What works well

Kept after the improvements section because §1 already covered the headline, but
these are real strengths:

### 3.1 Lazy model pull

Not downloading ~8 GB at setup for modalities the user may never touch is the
right default, and the skill is explicit about why. This is the decision most
likely to be second-guessed and it is correct.

### 3.2 Marker-fenced idempotent block

```
<!-- BEGIN amd-skills:local-ai-use -->
<!-- END amd-skills:local-ai-use -->
```

Replace-in-place rather than append is the difference between a skill that can
be re-run and one that accretes garbage. Instructing hand-editors to preserve
the exact markers is a nice touch.

### 3.3 The anti-shortcut instruction

"**Always run this script first — even if Lemonade is already installed and the
server is already running, and even before generating a single image**" plus the
matching checklist line ("generating an image alone does not complete the
skill") anticipates the specific way an agent would cut this skill short. That
is good skill-authoring instinct — it defends against the agent, not just the
environment.

### 3.4 The old-CLI shadowing section

The uninstall matrix by install channel, plus "never try to drive or auto-remove
it for the user," plus the repeated "never `pip install lemonade-sdk`, that is a
separate older release line" — this is hard-won and well placed. The
capability-based detection that backs it is what makes it robust.

### 3.5 The stalled-pull troubleshooting row

> `lemonade pull` keeps printing `Progress: NN%` but never finishes … the write
> error may surface only in the server log while the console keeps showing
> progress

Correct root cause, the right diagnostic (`/api/v1/system-info` for `models_dir`
and `free_bytes`), and a pointer to where the real error hides. Nobody writes
this without having lost an afternoon to it.

### 3.6 Explicit non-silent-fallback policy

"Only fall back to a cloud API after one local attempt has failed *and* the user
has been told" — correct for a skill whose entire premise is cost predictability.
Silent fallback would make the skill worse than useless, since the user would
believe they had stopped paying.

### 3.7 Honest scoping

"This skill does not redirect chat tokens; it only redirects the multimodal calls
that would otherwise leave the machine" is stated twice. Given the description
leads with saving money, being upfront that the largest token cost is untouched
is the right kind of honesty.

---

## 4. Planned live testing

Not yet run on this box — §2.1 and §2.2 predict a live run would damage a
working configuration, so scratch-first.

| # | Test | Effort | Settles |
|---|---|---|---|
| T1 | `setup_local_ai.py` in an empty scratch dir: clean-slate behavior, output legibility, does it correctly no-op against an already-running **system** `lemond` (vs `--user`) | ~30 min | §2.9, general |
| T2 | Re-run idempotence: run with `--stt-model X`, then re-run bare; check whether the customisation survives | ~10 min | §2.9 |
| T3 | Cascade behavior: run at a nested dir under a parent that already has the block; observe which file is written and whether the parent is detected | ~30 min | §2.3 |
| T4 | Merge against a throwaway branch of `~/git` with the real cascading `AGENTS.md`; diff the result | ~30 min | §2.1, §2.3 |
| T5 | `lemonade backends install sd-cpp:rocm` on gfx1151 — does the troubleshooting row's fix actually work on this hardware? | ~30 min | troubleshooting table |

T5 is worth calling out separately: the skill asserts a specific remedy for slow
CPU image generation on AMD hardware, and this box is exactly the hardware that
claim is about. I can give a definitive yes/no.

---

## 5. Summary

The install-and-detect half of this skill is **verified working** on real
hardware at a version beyond what it documents, and the capability-based probe
is the design decision that earned that. The AGENTS.md mechanism is sound, and
the troubleshooting content is unusually good.

The weakness is one-directional configuration: the skill writes but never reads.
No discovery of what is already serving (§2.1), no note that image generation
shares the GPU with LLM inference (§2.2), and no model for a nested `AGENTS.md`
cascade (§2.3). All three have the same root cause and the same shape of fix — a
single discovery step against `GET /api/v1/health` and `/api/v1/models` before
deciding anything — which would also resolve most of §2.5 and §2.6 as a side
effect.

That one addition would take this from "good for a fresh machine" to "safe on a
machine that already matters."
