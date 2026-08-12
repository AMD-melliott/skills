# Feedback — `local-ai-app-integration`

**Reviewer:** Matt Elliott
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy

Desk review of `SKILL.md` and `reference.md` against a live 11.5.2 stack and a
set of candidate host applications. Findings marked **[unverified]** are
predictions the test plan in §4 will settle; everything else is confirmed
against the running server.

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

**Suggested fix**, three parts:

1. Replace the empty-200 rows in Step 6, Step 7, and the checklist with the
   auto-pull behaviour.
2. **Keep the explicit `POST /api/v1/pull` step** — it is still right, for
   better reasons: predictable timing, a progress indicator that can cover the
   download, and offline installs. Rewrite its justification around *latency
   control* rather than *silent failure*.
3. Revisit the 120 s figure, or say plainly that the timeout must exceed a
   worst-case model download unless the model is pulled up front.

Scope: one model, one recipe (`llamacpp`), one host, at 11.5.2. Which release
changed this is unknown, and some recipe or size may still produce empty-200.
Reported as "did not reproduce here", not "cannot happen".

Related, and confirmed in the same run: **`/api/v1/models` alone is not the full
catalog.** It returns only local models (23 here); the registry has 145.
`GET /api/v1/models?show_all=true` returns all of them. The skill calls
`/api/v1/models` "the only authoritative model list" — a reader validating a
user-supplied model name gets a false negative for any of the 122 catalog models
not yet downloaded.

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

**Suggested fix.** Correct the row and note that prefixes are not uniform:

| Existing client | New `base_url` | Resulting path |
|---|---|---|
| `openai-python` / `openai-node` | `http://127.0.0.1:{port}/api/v1` | `/api/v1/chat/completions` |
| `@anthropic-ai/sdk` | `http://127.0.0.1:{port}` | `/v1/messages` |

> **Path prefixes are not uniform.** OpenAI-compatible routes live under
> `/api/v1`; the Anthropic Messages route is served at `/v1/messages`. Set
> `base_url` so the SDK's own path suffix resolves correctly, and verify with
> one real request before wiring up the rest of the app.

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

**Suggested fix.** One row in the Step 5 table and one in Step 7:

| Modality | Path |
|---|---|
| Reranking | `{port}/api/v1/reranking` — **not** `/v1/rerank`, despite that being the common convention |

| Symptom | Cause | Recovery |
|---|---|---|
| `/v1/rerank` 404s while chat works | Lemonade names the route `reranking` | Use `/api/v1/reranking`. The per-model back-port also serves `/v1/rerank`, but the proxy does not |

Worth noting for AMD's own consideration: aliasing `rerank` → `reranking` on the
proxy would remove the defect entirely and cost nothing.

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

**Suggested fix.** Either confirm and document the Linux `flm` install command
explicitly, or mark the row "Windows only" and note that Linux NPU ASR currently
runs as a standalone FastFlowLM process outside lemond — which has real
consequences here, since a standalone process is not something the Step 4
launcher supervises.

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

### 2.5 MEDIUM — The one-app-one-server assumption is never stated

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

### 2.7 MEDIUM — Version currency **[unverified]**

Examples reference `v10.8.0`; live is 11.5.2. Unverified at 11.x: `POST
/api/v1/install` body shape, `POST /api/v1/pull` behaviour, `GET
/api/v1/system-info` field names (the skill leans on it for the recipe/backend
`installed` / `installable` probe), and the Step 2 model IDs.

The skill is already appropriately humble about `/api/v1/load` changing shape
between releases; the same caution should extend to the endpoints it does tell
you to call.

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

### 2.9 LOW — Step 1 numbering

"Record three things before continuing" is followed by a four-item list. The
fourth (API-key gating) is important and should be counted.

### 2.10 LOW — Shutdown guidance is inverted from the usual convention

> On app exit, `proc.terminate()` (Unix) or `proc.kill()` (Windows).

On POSIX, `terminate()` sends SIGTERM (graceful) and `kill()` sends SIGKILL. On
Windows, Python's `subprocess` maps both to `TerminateProcess`, so they are
equivalent. Written as an OS split, it reads as though Windows requires the
harsher call, when the real distinction is that Windows has no graceful
equivalent.

**Suggested fix.** Rewrite as: `terminate()`, then `wait(timeout=…)`, then
`kill()` as a fallback — and note that on Windows the two are the same call, so
the wait is what actually matters. This also fits "lemond flushes config and
exits cleanly within a couple of seconds."

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

## 4. Planned testing

| # | Test | Effort | Settles |
|---|---|---|---|
| T1 | Namespace/endpoint sweep at 11.5.2 — **done**; confirmed the `messages` 404 and corrected the rerank finding | done | §2.1, §2.2 |
| T2 | `lemonade:` backend for `judge.py` — **done**; works in +40 lines, §2.1 reproduced as a negative control | done | §2.1, §2.8 |
| T3 | `lemonade backends install flm:npu` on Linux | 30 min | §2.4 |
| T4 | Skip the pull step; confirm the empty-200 failure reproduces at 11.5.2 | 15 min | §1.2 |
| T5 | *(folded into T1)* — rerank confirmed working at `/api/v1/reranking`; `/api/v1/rerank` 404s | done | §2.2 |
| T6 | Full integration into `instinct-dash`, run under `npm run dev:ui` **without** excluding `vendor/` from the Vite watcher | half day | §1.8, §2.8, progress UI |

T2 is also complete — see §3.1. T1 confirmed §2.1, corrected §2.2 from "rerank needs the
back-port" to "rerank is named `reranking`", and established that `/api/v1` and
`/v1` are otherwise aliases — so the skill's uniform advice is right everywhere
except the two routes now documented above.

T2 is the highest-value remaining item: a real integration on a real client that
already meets the precondition.

T4 and T6 are deliberately *reproduction* tests of the skill's own warnings.
Confirming a documented hazard is real at 11.5.2 is as useful as finding a new
one, and much cheaper.

---

## 5. Summary

The best-written of the three. The organising insight — that this integration
fails silently at five distinct stages, so the job is instrumenting each
transition — is correct and applied consistently rather than stated once. The
empty-200 diagnosis, the mandatory 120s timeout with its reason, the
`resources/` warning, and the file-watcher hazard are all things a reader could
not derive from the API docs.

Two confirmed defects come from the skill's uniform `{port}/api/v1` model not
matching the server's actual route table: the `@anthropic-ai/sdk` 404 (§2.1,
`messages` is `/v1`-only) and the `reranking` naming divergence (§2.2). Both are
one-line fixes. The absent model of coresidency and concurrency (§2.5, §2.6) is
the larger structural gap.

Step 1's survey patterns are the other actionable defect (§2.3): they find
vendor SDKs but miss hand-rolled HTTP clients — the failure mode most likely to
make an agent decline a job it should take, and the reason a good candidate host
sitting in `strix-halo-bench` is invisible to the skill's own discovery step.

Separately and more strategically: the topology I actually run — one server,
many networked consumers, plenty of commercial traffic to redirect — is served
by neither this skill nor `local-ai-use` (§3.2). Worth a conversation about
catalog coverage independent of any edit here.
