# Feedback — `local-ai-use`

**Reviewer:** Matt Elliott
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy

Desk review of `SKILL.md`, `reference.md`, `templates/local-ai-rule.md`, and
`scripts/setup_local_ai.py`, plus a live environment probe. Findings marked
**[unverified]** are predictions the test plan in §4 will settle;
`setup_local_ai.py` has deliberately not been run here, because §2.1 predicts it
would damage a working configuration.

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

### 2.2 HIGH — "Run once per workspace" is undefined for an `AGENTS.md` cascade **[unverified]**

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
- Does the script detect an existing `amd-skills:local-ai-use` block in a
  *parent* `AGENTS.md`? Reading the script, it looks for markers in the target
  file only. **[unverified]**
- The mirror list offers `CLAUDE.md` / `.cursor/rules/` / `GEMINI.md`. A user
  with two of those now has two copies that drift on the next run.

**Suggested fix.** State the rule: the block goes in the nearest `AGENTS.md` at
or above the working directory; if one exists in a parent, update that rather
than adding a second. Have the script print which file it wrote and the resolved
model IDs — one line that makes the cascade legible.

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

### 2.4 MEDIUM — Back-ports are invisible, so the endpoint picture is incomplete

The rule template points every call at `http://localhost:13305/api/v1/...`. But
Lemonade runs per-slot back-ends on their own ports, and not everything is
proxied. Live here:

```
:8001  Qwen3-Embedding-0.6B-Q8_0        embedding:1
:8002  bge-reranker-v2-m3-Q8_0          reranking:1
:8003  Qwen2.5-VL-7B-Instruct-Q4_K_M    llm:1
```

`/v1/rerank` lives on the back-port, **not** the `:13305` proxy, and the port is
assigned dynamically — it must be discovered from `/api/v1/health`
(`backend_url` per loaded model) rather than hardcoded.

This does not break the three modalities the skill covers today (images, TTS,
STT are proxied). It matters because `reference.md` invites extension, and the
next modality a user reaches for is embeddings or rerank — and because a reader
comes away believing `:13305/api/v1` is the whole surface, which is not true.

**Suggested fix.** A paragraph in `reference.md`: Lemonade serves some endpoints
from per-slot back-ports; discover them from `GET /api/v1/health` rather than
assuming `:13305`. Name `/v1/rerank` explicitly.

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

Pop!_OS 24.04 works fine via the documented PPA path. A user on Mint, Pop!_OS,
or elementary reading "Ubuntu/Debian x64" may assume they are unsupported.

### 2.8 LOW — `--no-install` is under-documented

It appears once, in Prerequisites. It does not appear in the opinionated path,
the troubleshooting table, or the Step 1 flow — despite being the correct flag
for a common case: a managed or shared machine where the agent should not run
`sudo apt-get install`. Worth a row in Step 1.

### 2.9 LOW — State what the idempotence claim excludes **[unverified]**

"Re-running it on a fully configured workspace is a no-op apart from a
healthcheck" is a strong claim. If a re-run also re-resolves model IDs from
flags, then a bare re-run after a customised first run would silently revert to
defaults. If true, call it out; if false, saying so explicitly would reassure.

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

## 4. Planned testing

Scratch-first: §2.1 and §2.3 predict a live run would damage a working
configuration.

| # | Test | Effort | Settles |
|---|---|---|---|
| T1 | `setup_local_ai.py` in an empty scratch dir: clean-slate behaviour, output legibility, correct no-op against an already-running **system** `lemond` (vs `--user`) | 30 min | §2.9, general |
| T2 | Re-run idempotence: run with `--stt-model X`, then re-run bare; does the customisation survive? | 10 min | §2.9 |
| T3 | Cascade: run at a nested dir under a parent that already has the block; which file is written, is the parent detected? | 30 min | §2.2 |
| T4 | Merge against a throwaway branch of `~/git` with the real cascading `AGENTS.md`; diff the result | 30 min | §2.1, §2.2 |
| T5 | `lemonade backends install sd-cpp:rocm` on gfx1151 — does the troubleshooting row's fix work on this hardware? | 30 min | troubleshooting table |
| T6 | Endpoint/namespace sweep: which prefix and port serves each documented endpoint at 11.5.2 | 45 min | §2.4, §2.6 |

T5 and T6 are worth calling out. T5 tests a specific remedy the skill asserts
for AMD hardware, on exactly the hardware that claim is about — a definitive
yes/no. T6 is shared with the `local-ai-app-integration` review, where the same
namespace gap produces a confirmed 404.

---

## 5. Summary

The install-and-detect half is **verified working** on real hardware at a
version beyond what it documents, and capability-based probing is the design
decision that earned that. The `AGENTS.md` mechanism is sound and the
troubleshooting content is unusually good.

The weakness is one-directional configuration: the skill writes but never reads.
No discovery of what is already serving (§2.1), no model for a nested cascade
(§2.2), no note that image generation shares the GPU with LLM inference (§2.3),
and an incomplete picture of Lemonade's endpoint surface (§2.4). The first three
share a root cause and a fix — a single discovery step against
`GET /api/v1/health` and `/api/v1/models` before deciding anything — which also
resolves most of §2.5 and §2.6.

That one addition takes this from "good for a fresh machine" to "safe on a
machine that already matters."
