# Feedback — `local-ai-app-integration`

**Reviewer:** Matt Elliott
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy

Review of `SKILL.md` and `reference.md` against a live 11.5.2 stack and a set of
candidate host applications. Everything below is confirmed against the running
server unless marked **[unverified]**; §4 records what was measured and what was
deliberately not run.

**This document holds design feedback, open questions, and research results
only.** Reproduced mechanical defects were submitted separately as a pull
request:

| PR | Covers |
|---|---|
| `fix(local-ai-app-integration): correct endpoint paths, Linux NPU row, and unpulled-model behaviour` | `@anthropic-ai/sdk` `base_url` 404 (§2.1); `reranking` vs `rerank` (§2.2); the Linux NPU row (§2.4); the unpulled-model behaviour change and its collision with the 120 s timeout (§2.0); `?show_all=true` for full-catalog validation (§2.0); the Step 1 "three things"/four-item miscount (§2.9); the shutdown-signal framing (§2.10) |

The sections those cover are kept below in short form, because the *reasoning*
is what makes each fix reviewable — but the edits themselves are already in the
PR and need no action here.

---

## 1. What works well

The strongest-written of the three Lemonade skills. Its core insight — that a
local integration fails *silently* in five different places, so the job is
making each transition visible — is correct and consistently applied.

### 1.1 "health 200 ≠ ready" is the right organising principle

Step 6 states the real sequence plainly:

```
server spawn → health 200 → backend install → model download → model load → first result
```

and says outright that treating health=200 as ready is "the single biggest cause
of a broken-looking integration." Most integration guides stop at the health
check. Naming the four things that must *also* be true, and giving each a step,
is what makes this worth following rather than skimming.

### 1.2 The silent-empty diagnosis — excellent instinct, but see §2.0

> If inference returns an empty string / blank output with no HTTP error, the
> model was not downloaded.

The *shape* of this is the best thing in the skill: naming a failure that
returns HTTP 200, stating it three times, and making it diagnosable in advance
by requiring the first inference result be logged verbatim. That is the
difference between documenting a failure and preventing one.

It no longer reproduces at 11.5.2 — see **§2.0**, which is a correction to the
mechanism, not to the instinct.

### 1.3 "Do not call `/api/v1/load` at startup"

Counter-intuitive, correct, and justified rather than asserted: the request body
shape has changed between releases and a malformed call can destabilise the
server. **Confirmed at 11.5.2** — `/api/v1/load` no longer accepts
`{"model": "..."}`:

```
POST /api/v1/load {"model":"Definitely-Not-A-Real-Model-XYZ"}
  → 400 {"error":{"code":"invalid_request",
         "message":"Invalid request: [json.exception.type_error.302] type must be string, but is null"}}
```

Keep this advice regardless of what else changes. Pairing it with "loading is the one step you let lemond do lazily —
pulling is not" draws a sharp line between two things that sound identical.

### 1.4 The 120-second timeout, with its reason

Making it one of three *mandatory* changes rather than a tuning note, and
explaining that the common 30s default is shorter than first-run model load — so
the failure presents as a blank UI indistinguishable from a broken integration —
is the right treatment. The per-client table means the reader cannot get it
wrong through ambiguity.

### 1.5 Per-stage logging as a first-class requirement

```
[lemond] Starting on port <port>
[lemond] Healthy on port <port>
[lemond] <recipe>:<backend> installed
[lemond] Pulling model <name>...  →  Model <name> ready
[local]  <modality> result: <value>
```

with "build the logging in from the start — not as an afterthought when
something breaks," and the observation that without it "'nothing happened' is
indistinguishable from 'broke at stage 3'." The most transferable advice in the
skill, placed early enough to change what the reader builds.

### 1.6 Release-asset lookup instead of a hand-built URL

Naming the trap — the tag carries a leading `v` but the asset filename strips
it, so a constructed URL 404s — and giving working PowerShell/bash that queries
the GitHub API by stable name pattern. The PowerShell sanity check is a nice
touch:

```powershell
if (-not (Test-Path vendor\lemonade\resources\*.json)) { throw "resources/ missing — re-extract and copy again" }
```

### 1.7 The `resources/` warning

> Copying only the binary produces a server that looks healthy but cannot
> function.

Same theme as §1.1 and §1.2 — a failure that passes the obvious check.

### 1.8 The dev-mode file-watcher caveat

Lemond writes config and cache files at runtime; a watcher (Tauri, Electron,
Next.js, Vite) picks them up, restarts the app, kills the subprocess, and spawns
a new one on a new port — "silently breaking any in-flight transcription." A
genuinely non-obvious interaction between two unrelated systems.

### 1.9 Local mode requires no cloud key — treated as a property, not an edge case

> This is a defining property of local mode, not an edge case.

Then made concrete: skip the key-entry screen, short-circuit empty-key
validators, re-enable the gate only for cloud mode. Step 1 pre-stages it by
asking the surveyor to record every API-key gate up front — the fix is set up
two steps before it is needed.

### 1.10 Honest scope boundaries

Runtime hardware fallback is out of scope, bundle Vulkan. "Having an NPU does
not mean every recipe supports NPU." System-wide Lemonade is a different
problem. Also: `server_models.json` can be stale, and `GET /api/v1/models` on a
running instance is the only authority — a discipline the sibling `local-ai-use`
should adopt for its hardcoded model IDs.

---

## 2. What needs improvement

Sections 2.1 and 2.2 are confirmed against a live 11.5.2 server. Both are cases
where the skill's uniform `{port}/api/v1` model does not match the route table
the server actually serves.

For context, the full namespace map: `/api/v1/*` and `/v1/*` are aliases on the
proxy for **every** route except `messages` (`/v1` only) and `metrics` (root
only). So the skill's `/api/v1` advice is right almost everywhere — which is
exactly why the two exceptions are easy to miss when writing a uniform table.

### 2.0 HIGH — The silent-empty failure does not reproduce at 11.5.2; a worse one replaced it (confirmed)

Step 6, the Step 7 recovery table, and the verification checklist all rest on:

> Lazy-load only loads weights that are **already downloaded**. If the model was
> never pulled, the first inference does not error — lemond returns an empty /
> blank result with HTTP 200.

Tested directly. `Tiny-Test-Model-GGUF` is in the catalog with
`downloaded: false`:

```
POST /api/v1/chat/completions {"model":"Tiny-Test-Model-GGUF","messages":[...]}
  → HTTP 200   time=9.61s   657 bytes
  → {"choices":[{"message":{"content":"I'm glad to be sure!","role":"assistant"}}], ...}

GET /api/v1/models?show_all=true  →  Tiny-Test-Model-GGUF downloaded: True
```

**Lemonade downloaded the weights inside the inference request and returned a
correct completion.** No empty body.

**The replacement hazard is worse, and the skill does not cover it.** First
inference can now block for the duration of a model download. The tiny test
model took 9.6 s; a 4B GGUF over a domestic link is minutes. So the
**mandatory 120-second timeout (§1.4) is likely insufficient** in exactly the
first-run scenario it was written for — and the symptom is a client timeout with
no output, which looks identical to the failure it replaced.

*Fixed in the PR:* both behaviours are now documented, both cured by the same
explicit pull, and the pull step is rejustified around **latency control**
rather than silent failure — it was always the right instruction, just for a
different reason. The related catalog point is fixed there too:
`GET /api/v1/models` returns downloaded models only (23 here against 145
catalogued), so validating a user-supplied model name needs `?show_all=true`.

**What the PR does not settle, and AMD should.** Scope of my test was one model,
one recipe (`llamacpp`), one host, at 11.5.2 — so this is "did not reproduce
here", not "cannot happen". Which release changed the behaviour is unknown, and
some recipe or model size may still produce empty-200. The open design question
is the **120-second figure itself**: it is now a number that must exceed a
worst-case model download over an unknown link, which is not a number anyone can
pick. Either the skill tells the reader to pull before setting a timeout at all
(making 120 s a post-pull inference budget, which is defensible), or the pull
step needs to be non-optional rather than recommended.

### 2.1 HIGH — The `@anthropic-ai/sdk` base_url produces a guaranteed 404 (confirmed)

The Step 5 client table says:

| Existing client | New `base_url` |
|---|---|
| `@anthropic-ai/sdk` | `http://127.0.0.1:{port}/api/v1` |

The Anthropic SDK appends `/v1/messages` to `base_url`, so that configuration
requests `/api/v1/v1/messages`. Probed against live 11.5.2:

```
POST /api/v1/messages      → 404  {"error":{"message":"The requested endpoint does not exist", ...}}
POST /api/v1/v1/messages   → 404
POST /v1/messages          → 200  {"content":[{"text":"Hello! How can I assist you today","type":"text"}], ...}
```

Control: `POST /api/v1/chat/completions` with a real model returns 200, so the
server and model are fine — the path is wrong.

**Reproduced end-to-end in a real client.** Implementing this skill's Step 5
against an existing Anthropic-Messages application (see §3.1) and setting the
base URL to the documented value produces exactly the doubled path:

```
$ JUDGE_LEMONADE_BASE_URL=http://127.0.0.1:13305/api/v1 python3 judge.py …
transport: status=404 error=HTTP Error 404: Not Found;
raw={"error":{"message":"The requested endpoint does not exist",
              "path":"/api/v1/v1/messages","type":"not_found"}}
```

With the bare host and port, the same client returns a parseable verdict.

**Lemonade does speak Anthropic Messages, but serves it from `/v1/messages`,
outside the `/api/v1` prefix.** The correct `base_url` for `@anthropic-ai/sdk`
is `http://127.0.0.1:{port}` with no path suffix.

This matters more than a typo because the skill presents `/api/v1` as a uniform
base for every client in the table. An Anthropic-SDK app following it verbatim
404s on its first call — during the exact cold-start window where the skill has
trained the reader to suspect an unpulled model or a short timeout instead.

*Fixed in the PR* — the row is corrected, the whole Step 5 table now shows what
each `base_url` resolves to rather than only the base, and a 404 body carrying a
`path` field is named in Step 7 as a routing mistake rather than a missing model.

**Worth AMD's consideration beyond the doc fix:** the underlying cause is that
`messages` is the one route that does not exist under `/api/v1`. Aliasing it
there would make the skill's uniform-prefix model true, and would cost nothing.

### 2.2 MEDIUM — Rerank is exposed as `reranking`, diverging from every other implementation (confirmed)

Not a prefix problem — a naming one. Verified functionally at 11.5.2:

```
POST /api/v1/reranking  → 200  {"model":"bge-reranker-v2-m3-GGUF","object":"list",
                                "results":[{"index":0,"relevance_score":-3.714}, ...]}
POST /v1/reranking      → 200
POST /api/v1/rerank     → 404
POST /v1/rerank         → 404
POST :8002/v1/rerank    → 200   (the llama.cpp back-port serves both spellings)
```

`/v1/rerank` is the path used by Jina, Cohere, vLLM, and llama.cpp itself.
Lemonade's proxy exposes only `reranking`; the back-port it supervises serves
both. So an app written against the convention — or against the behaviour of the
back-port it can see in `GET /api/v1/health` — 404s on the proxy.

Retrieval apps (embeddings + rerank) are a common shape for this skill's
audience, and the skill's premise is that three changes suffice. A silent path
rename is exactly the kind of thing that premise does not survive.

*Fixed in the PR* — the route table now carries `/api/v1/reranking` and names
what 404s.

**Worth AMD's consideration:** aliasing `rerank` → `reranking` on the proxy
would remove the defect at the source rather than documenting around it. The
back-port already serves both spellings, so the proxy is the only place where
the convention breaks.

### 2.3 HIGH — Step 1's survey patterns miss hand-rolled HTTP clients

Step 1 tells the surveyor to search for:

```
openai, OpenAI(, chat.completions, responses.create
anthropic, Anthropic(, messages.create
api.openai.com, api.anthropic.com, localhost:11434
OPENAI_API_KEY, ANTHROPIC_API_KEY
```

Running exactly that across four AI-adjacent repos here — `instinct-dash`,
`multitool`, `strix-halo-bench`, `octant-private` — returns **zero source hits**.

That result is misleading. `strix-halo-bench/scripts/common/judge.py` is a
first-class cloud AI client:

```python
"""Configurable LLM judge for benchmark prompt outputs.
... calls a configured judge backend over the Anthropic Messages wire format ...

Backend selectors:
  none                     -- emit a skip verdict; no network calls.
  local:<provider,model>   -- POST to JUDGE_LOCAL_BASE_URL (default
                              http://127.0.0.1:3456) using the local CCR key
  gateway:<model>          -- POST to JUDGE_BASE_URL ... with JUDGE_API_KEY
"""
```

It sends `POST /v1/messages` with `x-api-key` and `anthropic-version:
2023-06-01`. Squarely the shape this skill targets. Every Step 1 pattern misses
it because it uses **raw HTTP with project-specific env var names**
(`JUDGE_API_KEY`, `JUDGE_BASE_URL`) rather than a vendor SDK.

Step 1 decides whether the skill applies at all. An agent that runs those
patterns, gets nothing, and concludes "this app has no cloud AI to replace"
declines a job it should have taken. Vendor-SDK imports are the easy case;
hand-rolled HTTP clients with local naming conventions are common in exactly the
research, benchmark, and internal-tooling code most likely to want a local
backend.

**Suggested fix.** A second, behavioural tier to the Step 1 search:

> **If the SDK patterns above return nothing, search by wire protocol instead —
> the app may use raw HTTP:**
>
> - Path literals: `/v1/messages`, `/v1/chat/completions`, `/v1/embeddings`
> - Anthropic headers: `anthropic-version`, `x-api-key`
> - Generic config names: `*_API_KEY`, `*_BASE_URL`, `*_MODEL`, `base_url=`
> - Any HTTP client (`httpx`, `requests`, `fetch`, `curl`) posting JSON with a
>   `messages` array
>
> A hand-rolled client is still a client. If the app already routes model calls
> through one config point, it may be *easier* to re-point than an SDK-based app.

### 2.4 HIGH — The Linux NPU row is wrong (confirmed)

Step 2's profile table lists:

| App's primary need | Default model | Recipe |
|---|---|---|
| Speech-to-text (Linux NPU) | `whisper-v3-turbo-FLM` | `flm` |

On this box — an XDNA NPU on Linux, the exact target — NPU ASR works, but not as
a Lemonade recipe. It runs as a standalone FastFlowLM host process:

```
flm serve qwen3-tk:4b --embed 1 --asr 1     # :52625
```

serving `/v1/chat/completions`, `/v1/embeddings`, and
`/v1/audio/transcriptions` from one process that owns the single AMDXDNA
context, managed as a separate slot precisely because it sits outside Lemonade's
accounting.

Note the skill only shows `flm:npu` in a **Windows** packaging example
(`# Windows NPU path only`), which contradicts the Linux row above it.

**Confirmed functionally.** All three NPU backends refuse to install at 11.5.2:

```
lemonade backends install whispercpp:npu   → Requires Windows
lemonade backends install ryzenai-llm:npu  → Requires Windows
lemonade backends install flm:npu          → Requires AMD XDNA 2 AMD NPU
```

The first two are honest platform gates. The third is misleading: it names a
*hardware* requirement this machine meets — a Ryzen AI MAX+ PRO 395 with an
XDNA 2 NPU — while the actual blocker is that `system-info` reports
`amd_npu.family: ""` on Linux, so the device check cannot pass regardless of the
hardware. A user with the exact NPU the message asks for is told they do not
have it.

*The wrong row is removed in the PR.* Two things are left for AMD:

1. **The `flm:npu` message should name the real gate.** "Requires Windows"
   would be accurate and would cost one string; as written it sends a user
   with correct hardware to look for a hardware problem.
2. **Linux NPU ASR does work — outside lemond.** It runs as a standalone
   FastFlowLM host process (`flm serve qwen3-tk:4b --embed 1 --asr 1`, `:52625`)
   serving `/v1/chat/completions`, `/v1/embeddings`, and
   `/v1/audio/transcriptions` from one process that owns the single AMDXDNA
   context. That has a real architectural consequence for *this* skill: a
   standalone process is not something the Step 4 launcher supervises, so the
   whole spawn/health/shutdown lifecycle the skill builds does not cover it.
   Either the skill says Linux NPU is out of scope, or it needs a second
   supervision path.

### 2.5 HIGH — No platform preflight: the skill ships to unknown hosts and never says the host is a variable

The skill has **no Prerequisites section**. Step 2 says to bundle Vulkan as "the
universal fallback so the app works on any machine," and Step 3 says to install
`llamacpp:rocm` at first run when `system-info` reports `installable`. That
inherits every host-level requirement an AMD inference box has, with no
acknowledgement anywhere that the host might not be ready.

Searching all three Lemonade skills for host-layer terms returns **zero** hits:
`iommu`, kernel or boot parameters, BIOS/UEFI, GTT, VRAM sizing, `power_dpm`,
`HSA_OVERRIDE_GFX_VERSION`, hugepages, `/dev/kfd`, `/dev/dri`, `crun`,
`keep-groups`, sysfs, driver or kernel version. Meanwhile `backend` appears 83
times, `NPU` 48, `ROCm` 17. The skills are thoroughly **backend-aware** and
entirely **platform-unaware** — everything lives at Lemonade's abstraction, and
the machine underneath is assumed correct.

**Why this belongs in *this* skill's scope specifically.** It is the one skill
that ships inference onto a machine the developer will never see. A
system-wide-server user can be told to fix their own host; an app's end user
cannot.

#### The gap matters because these are silent failures — the skill's own theme

The best thing about this skill is that it hunts failures which return success.
There is an entire class of those *below* Lemonade, and they present with the
same symptoms the skill teaches you to diagnose differently. From tuning notes
for this hardware:

> "Failure is SILENT and looks like success. With the HIP libs unreachable,
> `libggml-hip.so` simply never loads and llama.cpp falls back to CPU — exit
> code 0, sensible-looking output, **16x slower prefill** (65.89 vs 1043.63
> pp512)." And: "**`rocminfo` succeeding does NOT mean HIP works**."

An app built to this skill would report that as working. The `[local] <modality>
result:` log line from Step 4 would show a correct answer. Every verification
checkbox would pass. The user just gets a product that is 16× too slow.

Others in the same family, all of which surface as a crash, a hang, or "it's
slow" rather than a diagnosable error:

| host condition | how it presents |
|---|---|
| rootless podman on `runc` instead of `crun` | `/dev/kfd` maps to `nobody`; container starts fine, no GPU |
| `--device /dev/dri` passed as a directory | podman does not recurse it; devices silently absent |
| container ROCm userspace ≠ host kernel driver | segfault, reads as an app bug |
| `linux-firmware-20251125` on Strix Halo | "instability, crashes, or arbitrary failures" |
| kernel < 6.16.9 | GPU sees ~15.5 GB instead of the full unified pool |
| kernel < 6.18.4 | gfx1151 stability bug |
| GTT aperture == swapout trigger | hard host wedge instead of a clean OOM |
| stale `HSA_OVERRIDE_GFX_VERSION` in the environment | hard iGPU hang, reboot required |

#### The cheapest fix uses a call the skill already makes

`GET /api/v1/system-info` — invoked eleven times across these skills, always to
read `recipes[].backends[].state` — also returns the platform:

```json
"amd_gpu": [{ "available": true, "family": "gfx1151", "integrated": true,
              "virtual_mem_gb": 124.0, "vram_gb": 0.5 }]
```

`virtual_mem_gb` and `vram_gb` are the GTT ceiling and the BIOS framebuffer. A
misconfigured host shows different numbers. Reading `devices` alongside
`recipes` costs nothing and catches a real class of problem.

It is only a partial preflight — kernel version, firmware version, and IOMMU
state are not exposed — which is worth saying plainly rather than implying the
check is complete.

**Suggested fix**, deliberately small:

1. Add a **Prerequisites** section. Even three lines: the host needs a working
   GPU driver stack; a backend reporting `installed` does not mean it is
   *functioning*; on Linux, rootless containers need `crun` and
   `--group-add keep-groups` for `/dev/kfd` access.
2. In Step 3's `system-info` probe, read `devices` as well as `recipes`, and log
   the resolved device — it becomes the first line of any support conversation.
3. Add one Step 7 recovery row:

| Symptom | Cause | Recovery |
|---|---|---|
| Inference works but is dramatically slower than expected | Backend installed but not actually engaged — the runtime silently fell back to CPU | Confirm the GPU is in use (`gpu_busy_percent`, backend logs). A green `system-info` state and a successful `rocminfo` both still permit a silent CPU fallback |

#### A caveat worth stating to AMD

Most of the specific values above are genuinely out of scope here, and the
source material contradicts itself badly — `amd_iommu=off` vs `iommu=pt` *within
one repository*, two different GTT ceilings, host reserve of 4 GiB vs 12 GiB,
`ttm.pages_limit` raise-vs-lower, `--mlock` documented unusable yet shipped in
live configs. That is not an argument for omitting the topic. It is an argument
that **AMD is the only party who can state it authoritatively**, and that it
deserves its own home — see §3.3.

### 2.5b MEDIUM — The one-app-one-server assumption is never stated

Each app spawns a private `lemond` on a random port with a fresh API key. Clean
and correct for a single desktop app. What happens when that breaks is not
stated, and it breaks easily:

- Two apps built with this skill on one machine → two lemond processes, two
  model caches (or a shared one, depending on `models_dir`), two copies of the
  same weights competing for one GPU.
- An app built this way on a machine that *already* runs a system-wide Lemonade
  — the skill routes that away for the initial choice, but says nothing about
  coexistence.

The `models_dir` guidance frames `./models` purely as a privacy choice, not as a
disk-and-VRAM cost. Two apps each bundling a 4B model is ~5 GB duplicated and
two model loads competing for one GPU.

**Suggested fix.** A subsection under Step 3's bundle decisions:

> **If more than one app on the machine may do this,** weigh `models_dir: auto`
> (shared cache — deduplicated weights, some coupling between apps) against
> `./models` (private, duplicated). Two lemond instances still compete for the
> same GPU regardless of cache choice; there is no cross-process arbitration.

### 2.6 MEDIUM — No concurrency or slot model

Related but distinct: even within one app, nothing says what happens when two
requests arrive at once, or when the app uses more than one modality.

Lemonade keeps separate slots per model class — embedding, transcription, tts,
reranking, image, llm — and loading one does **not** evict another. That is a
genuinely useful property for this audience: an app doing
transcribe-then-summarise can keep both resident. But memory adds up, and the
"pick one default profile, do not ship a buffet" advice reads as if only one
model is ever loaded.

**Suggested fix.** A sentence in Step 2: models of different classes stay
coresident rather than evicting each other, so a multi-modality app should size
memory for the sum, not the max. Turns an unstated risk into a stated design
input.

### 2.7 MEDIUM — Version currency (partly verified)

Examples reference `v10.8.0`; live is 11.5.2. Checked here and **holding**:
`GET /api/v1/system-info` field names (the recipe/backend
`installed` / `installable` probe the skill leans on), `POST /api/v1/pull`
behaviour, and `GET /api/v1/models`. Still **unverified**: `POST /api/v1/install`
body shape, and the Step 2 model IDs beyond the ones I exercised.

The skill is already appropriately humble about `/api/v1/load` changing shape
between releases — and that humility was earned, since it did change. The same
caution should extend to the endpoints it does tell you to call.

**Suggested fix.** State a tested-against version range. Since the skill
instructs the reader to fetch the *latest* release, a note that model IDs and
`system-info` fields should be confirmed against the version actually downloaded
would be consistent with its own `server_models.json` guidance.

### 2.8 LOW — "~30 lines and three changes" undersells the work **[unverified]**

The opening promises one ~30-line launcher, three client changes, one vendored
binary. The body then requires per-stage logging, a loading indicator covering
the whole cold-start sequence, bypassing every API-key gate, a first-run backend
install, a pull step, shutdown handling, and watcher exclusions. The
verification checklist has eleven boxes.

All justified — but a reader who budgets against the headline will be surprised,
and the risk is abandonment halfway, leaving exactly the half-configured state
the skill warns about.

**Suggested fix.** Keep the headline for the *core* change and add a clause:
"…plus first-run setup (backend install, model pull), progress UI, and lifecycle
handling — budget a day for a first integration." Honest scoping makes the skill
more likely to be finished, not less likely to be started.

### 2.9–2.10 LOW — Two wording fixes, both in the PR

- **Step 1 numbering.** "Record three things before continuing" is followed by a
  four-item list; the fourth (API-key gating) is load-bearing and should be
  counted.
- **Shutdown guidance.** "`proc.terminate()` (Unix) or `proc.kill()` (Windows)"
  reads as though Windows requires the harsher call. On POSIX `terminate()` is
  SIGTERM and `kill()` is SIGKILL; on Windows Python maps both to
  `TerminateProcess`, so they are the same call. Now written as terminate →
  `wait(timeout=5)` → kill, which is what the skill's own "lemond flushes config
  and exits cleanly within a couple of seconds" implies.

---

## 3. Candidate hosts and a catalog gap

### 3.1 `judge.py` is the ideal first integration host

Beyond being the §2.3 example, `judge.py` satisfies Step 1's hardest requirement
out of the box:

> **One single place** where the base URL and API key are constructed. If there
> isn't one, refactor to one before going further.

It already has that — `_resolve_backend()` returns an `(kind, model, endpoint,
headers)` tuple selected by a backend string — and it already has a `local:`
option pointing at a local CCR. Adding a `lemonade:` selector is close to the
minimal possible version of this integration, which makes it a good control: if
the "three changes" claim holds anywhere, it holds here. It also exercises §2.1
directly, since the judge speaks Anthropic Messages.

**Tested — it works, and the "three changes" claim broadly holds.** A
`lemonade:<model>` selector alongside the existing `none` / `local:` /
`gateway:` came to **+40 lines**, all additive, and returned a parseable verdict
with a correctly written sidecar on the first run. Against the three prescribed
changes:

| change | outcome |
|---|---|
| `base_url` | needed — but **not the documented value** (§2.1) |
| `api_key` | needed, inverted: loopback lemond is unauthenticated, so the right move was to send a key *only if* `LEMONADE_API_KEY` is set, rather than always |
| 120 s timeout | **already satisfied** — the client's `JUDGE_TIMEOUT_S` happened to default to exactly 120 |

Two qualifications. This was the easiest possible host — it already had the
single config point Step 1 demands *and* a pluggable-backend abstraction; an app
with neither would pay the refactor the skill mentions only in passing. And the
`api_key` row suggests the skill's framing assumes its own Step 4 launcher, which
mints a per-launch key; a system-wide server has no key at all, and the skill's
"set `api_key` to the launcher key" has no counterpart there.

Caveat: it is a batch harness, not a desktop app, so it did not exercise the
progress-UI or key-gating requirements, nor Steps 3–4 (vendoring, subprocess
launcher). This validates **Step 5 only**. `instinct-dash` (Fastify + React + Vite,
Playwright harness) is the secondary host for those, and is the right instrument
for the §1.8 watcher hazard since Vite is precisely the case that warns about.

### 3.2 The gap: one server, many networked consumers

Between the two local-AI skills:

- `local-ai-use` → one workspace, one agent, system-wide server.
- `local-ai-app-integration` → one app, one private embedded server.

Neither covers **one Lemonade instance, many consumers over a network** — a
common shape for anyone with a homelab or a shared team box.

Evidence it is unserved: my homelab repo deploys litellm, claude-code-router,
open-webui, and embedchain, all routinely calling commercial models, and
`grep -rilE 'lemonade|13305|strix' terraform/` returns **zero hits**. The fleet
has no on-ramp to the local Lemonade box, and neither skill provides one; this
one routes that user to a docs link and stops.

There is no shortage of traffic to redirect. What is missing is a skill for the
topology it runs in. The content would be specific: binding beyond loopback,
`LEMONADE_API_KEY` as a shared secret rather than a per-launch random, service
discovery, back-port exposure (§2.2), and cross-consumer concurrency (§2.6).

### 3.3 The other gap: "prepare an AMD host for local inference"

§2.5 identifies content that does not belong in any of the three skills but has
nowhere else to live: kernel and firmware minimums, IOMMU and unified-memory
boot parameters, BIOS framebuffer sizing, container runtime requirements for
`/dev/kfd` access, the ROCm/HIP environment, and how to tell a working GPU path
from a silent CPU fallback.

This is the natural fourth skill, and the catalog's most defensible gap — every
other skill in this family assumes its output. It is also the one topic where
AMD's authority is decisive: a community author guessing at
`amdgpu.gttsize` values will get them wrong, and the existing published guidance
already disagrees with itself.

Together with §3.2 (one server, many networked consumers) that is two catalog
gaps, both sitting *underneath* rather than beside the current skills.

---

## 4. Testing performed

| # | Test | Status | Settles |
|---|---|---|---|
| T1 | Namespace/endpoint sweep at 11.5.2 across all three namespaces | **done**; `messages` is `/v1`-only, rerank is `reranking`, everything else aliases | §2.1, §2.2 |
| T2 | `lemonade:` backend for `judge.py` — a real Anthropic-Messages client | **done**; +40 lines, all additive; §2.1 reproduced end-to-end as a negative control | §2.1, §2.8, §3.1 |
| T3 | `lemonade backends install {whispercpp,ryzenai-llm,flm}:npu` on Linux | **done**; all three refuse, exact strings in §2.4 | §2.4 |
| T4 | Skip the pull step; check whether empty-200 reproduces at 11.5.2 | **done**; it does not — first inference blocks and downloads instead | §1.2, §2.0 |
| T5 | *(folded into T1)* | done | §2.2 |
| T6 | Full integration into `instinct-dash` under `npm run dev:ui` without excluding `vendor/` from the Vite watcher | **not run** | §1.8, §2.8, progress UI |

**T6 is the one real gap, and it is deliberate.** It is the only test that would
exercise Steps 3–4 (vendoring, the subprocess launcher, shutdown) and the
progress-UI and key-gating requirements — everything T2 explicitly could not
reach, since `judge.py` is a batch harness with a pre-existing config point. It
is also the only way to confirm the file-watcher hazard in §1.8 rather than
taking it on trust.

It costs roughly half a day and would land in an unrelated repo. The findings
already in hand do not depend on it: nothing in §2 is contingent on the launcher
behaving as documented, and §2.8's "the headline undersells the work" claim is
*strengthened*, not weakened, by T2 having taken +40 lines on the easiest
possible host. I would rather flag it as untested than half-run it.

If AMD wants one more datapoint from this review, T6 is the one to ask for.

Everything else is settled. T4 was a reproduction test of the skill's own
headline warning and came back negative, which is the most consequential single
result here — confirming a documented hazard is real is as useful as finding a
new one, and finding it *replaced* is more useful still.

---

## 5. Summary

The best-written of the three. The organising insight — that this integration
fails silently at five distinct stages, so the job is instrumenting each
transition — is correct and applied consistently rather than stated once. The
empty-200 diagnosis, the mandatory 120s timeout with its reason, the
`resources/` warning, and the file-watcher hazard are all things a reader could
not derive from the API docs.

The reproduced defects — the `@anthropic-ai/sdk` 404, the `reranking` naming
divergence, the Linux NPU row, and the unpulled-model behaviour — are in the PR
and need no decision here.

What is left for AMD is structural, and it is one thing said three ways: the
skill models a **document** shipping to a **known** machine. §2.5 (no platform
preflight), §2.5b (one-app-one-server), and §2.6 (no concurrency or slot model)
are all the same absence. The skill is thoroughly backend-aware and entirely
platform-unaware, and it is the one skill in the family that ships inference
onto a machine its author will never see.

Step 1's survey patterns are the other actionable design gap (§2.3): they find
vendor SDKs but miss hand-rolled HTTP clients — the failure mode most likely to
make an agent decline a job it should take, and the reason a good candidate host
sitting in `strix-halo-bench` is invisible to the skill's own discovery step. I
found this by running the skill's own patterns and getting zero hits on repos I
knew contained cloud AI clients.

Separately and more strategically: the topology I actually run — one server,
many networked consumers, plenty of commercial traffic to redirect — is served
by neither this skill nor `local-ai-use` (§3.2). Worth a conversation about
catalog coverage independent of any edit here.
