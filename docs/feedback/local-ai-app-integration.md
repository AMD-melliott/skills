# Feedback on `local-ai-app-integration`

**Reviewer:** Matt Elliott
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy
**Embeddable artifact:** `lemonade-embeddable-11.5.2-ubuntu-x64.tar.gz` (`6843693` B, sha256 `936220519193a5cb6d3ac2199a8a8630bf87f36e297e2a5948a056e4c539340a`, both matching release metadata), extracted and run standalone on `:13399` alongside the system instance

Review of `SKILL.md` and `reference.md` against a live 11.5.2 stack, the
embeddable `lemond` artifact the skill tells you to vendor, and a set of
candidate host applications. Everything below is confirmed against the running
server or the extracted artifact unless marked **[unverified]** or explicitly
labelled as inferred; §4 records what was measured and what was deliberately not
run.

**This document holds design feedback, open questions, and research results
only.** Reproduced mechanical defects were submitted separately as a pull
request:

| PR | Covers |
|---|---|
| `fix(local-ai-app-integration): correct endpoint paths, Linux NPU row, and unpulled-model behaviour` | `@anthropic-ai/sdk` `base_url` 404 (§2.1); `reranking` vs `rerank` (§2.2); the Linux NPU row (§2.4); the unpulled-model behaviour change and its collision with the 120 s timeout (§2.0); `?show_all=true` for full-catalog validation (§2.0); the Step 1 "three things"/four-item miscount (§2.9); the shutdown-signal framing (§2.10) |

The sections those cover are kept below in short form, because the *reasoning*
is what makes each fix reviewable, but the edits themselves are already in the
PR and need no action here.

---

## 1. What works well

The strongest-written of the three Lemonade skills. Its core insight, that a
local integration fails *silently* in five different places, so the job is
making each transition visible, is correct and consistently applied.

### 1.1 "health 200 ≠ ready" is the right organising principle

Step 6 states the real sequence plainly:

```
server spawn → health 200 → backend install → model download → model load → first result
```

and says outright that treating health=200 as ready is "the single biggest cause
of a broken-looking integration." Most integration guides stop at the health
check. Naming the four things that must *also* be true, and giving each a step,
is what makes this worth following rather than skimming.

The sequence is one stage short. Health 200 also precedes model-cache-ready
(**§2.12**), which extends the principle rather than contradicting it.

### 1.2 The silent-empty diagnosis: excellent instinct, but see §2.0

> If inference returns an empty string / blank output with no HTTP error, the
> model was not downloaded.

The *shape* of this is the best thing in the skill: naming a failure that
returns HTTP 200, stating it three times, and making it diagnosable in advance
by requiring the first inference result be logged verbatim. That is the
difference between documenting a failure and preventing one.

It no longer reproduces at 11.5.2. See **§2.0**, which is a correction to the
mechanism, not to the instinct.

### 1.3 "Do not call `/api/v1/load` at startup"

Counter-intuitive, correct, and justified rather than asserted: the request body
shape has changed between releases and a malformed call can destabilise the
server. **Confirmed at 11.5.2:** `/api/v1/load` no longer accepts
`{"model": "..."}`:

```
POST /api/v1/load {"model":"Definitely-Not-A-Real-Model-XYZ"}
  → 400 {"error":{"code":"invalid_request",
         "message":"Invalid request: [json.exception.type_error.302] type must be string, but is null"}}
```

Keep this advice regardless of what else changes. Pairing it with "loading is the one step you let lemond do lazily,
pulling is not" draws a sharp line between two things that sound identical.

### 1.4 The 120-second timeout, with its reason

Making it one of three *mandatory* changes rather than a tuning note, and
explaining that the common 30s default is shorter than first-run model load, so
the failure presents as a blank UI indistinguishable from a broken integration,
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

with "build the logging in from the start, not as an afterthought when
something breaks," and the observation that without it "'nothing happened' is
indistinguishable from 'broke at stage 3'." The most transferable advice in the
skill, placed early enough to change what the reader builds.

### 1.6 Release-asset lookup instead of a hand-built URL

Naming the trap: the tag carries a leading `v` but the asset filename strips
it, so a constructed URL 404s, and giving working PowerShell/bash that queries
the GitHub API by stable name pattern. The PowerShell sanity check is a nice
touch:

```powershell
if (-not (Test-Path vendor\lemonade\resources\*.json)) { throw "resources/ missing: re-extract and copy again" }
```

### 1.7 The `resources/` warning

> Copying only the binary produces a server that looks healthy but cannot
> function.

Same theme as §1.1 and §1.2: a failure that passes the obvious check.

### 1.8 The dev-mode file-watcher caveat

Lemond writes config and cache files at runtime; a watcher (Tauri, Electron,
Next.js, Vite) picks them up, restarts the app, kills the subprocess, and spawns
a new one on a new port, "silently breaking any in-flight transcription." A
genuinely non-obvious interaction between two unrelated systems.

### 1.9 Local mode requires no cloud key: treated as a property, not an edge case

> This is a defining property of local mode, not an edge case.

Then made concrete: skip the key-entry screen, short-circuit empty-key
validators, re-enable the gate only for cloud mode. Step 1 pre-stages it by
asking the surveyor to record every API-key gate up front. The fix is set up
two steps before it is needed.

### 1.10 Honest scope boundaries

Runtime hardware fallback is out of scope, bundle Vulkan. "Having an NPU does
not mean every recipe supports NPU." System-wide Lemonade is a different
problem. Also: `server_models.json` can be stale, and `GET /api/v1/models` on a
running instance is the only authority, a discipline the sibling `local-ai-use`
should adopt for its hardcoded model IDs.

---

## 2. What needs improvement

Sections 2.1 and 2.2 are confirmed against a live 11.5.2 server. Both are cases
where the skill's uniform `{port}/api/v1` model does not match the route table
the server actually serves.

For context, the full namespace map: `/api/v1/*` and `/v1/*` are aliases on the
proxy for **every** route except `messages` (`/v1` only) and `metrics` (root
only). So the skill's `/api/v1` advice is right almost everywhere, which is
exactly why the two exceptions are easy to miss when writing a uniform table.

### 2.0 HIGH: The silent-empty failure does not reproduce at 11.5.2; a worse one replaced it (confirmed)

Step 6, the Step 7 recovery table, and the verification checklist all rest on:

> Lazy-load only loads weights that are **already downloaded**. If the model was
> never pulled, the first inference does not error. Lemond returns an empty /
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
first-run scenario it was written for, and the symptom is a client timeout with
no output, which looks identical to the failure it replaced.

*Fixed in the PR:* both behaviours are now documented, both cured by the same
explicit pull, and the pull step is rejustified around **latency control**
rather than silent failure. It was always the right instruction, just for a
different reason. The related catalog point is fixed there too:
`GET /api/v1/models` returns downloaded models only (23 here against 145
catalogued), so validating a user-supplied model name needs `?show_all=true`.

**What the PR does not settle, and AMD should.** Scope of my test was one model,
one recipe (`llamacpp`), one host, at 11.5.2, so this is "did not reproduce
here", not "cannot happen". Which release changed the behaviour is unknown, and
some recipe or model size may still produce empty-200. The open design question
is the **120-second figure itself**: it is now a number that must exceed a
worst-case model download over an unknown link, which is not a number anyone can
pick. Either the skill tells the reader to pull before setting a timeout at all
(making 120 s a post-pull inference budget, which is defensible), or the pull
step needs to be non-optional rather than recommended.

### 2.1 HIGH: The `@anthropic-ai/sdk` base_url produces a guaranteed 404 (confirmed)

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
server and model are fine. The path is wrong.

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
404s on its first call, during the exact cold-start window where the skill has
trained the reader to suspect an unpulled model or a short timeout instead.

*Fixed in the PR:* the row is corrected, the whole Step 5 table now shows what
each `base_url` resolves to rather than only the base, and a 404 body carrying a
`path` field is named in Step 7 as a routing mistake rather than a missing model.

**Worth AMD's consideration beyond the doc fix:** the underlying cause is that
`messages` is the one route that does not exist under `/api/v1`. Aliasing it
there would make the skill's uniform-prefix model true, and would cost nothing.

### 2.2 MEDIUM: Rerank is exposed as `reranking`, diverging from every other implementation (confirmed)

Not a prefix problem: a naming one. Verified functionally at 11.5.2:

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
both. So an app written against the convention, or against the behaviour of the
back-port it can see in `GET /api/v1/health`, 404s on the proxy.

Retrieval apps (embeddings + rerank) are a common shape for this skill's
audience, and the skill's premise is that three changes suffice. A silent path
rename is exactly the kind of thing that premise does not survive.

*Fixed in the PR:* the route table now carries `/api/v1/reranking` and names
what 404s.

**Worth AMD's consideration:** aliasing `rerank` → `reranking` on the proxy
would remove the defect at the source rather than documenting around it. The
back-port already serves both spellings, so the proxy is the only place where
the convention breaks.

### 2.3 HIGH: Step 1's survey patterns miss hand-rolled HTTP clients

Step 1 tells the surveyor to search for:

```
openai, OpenAI(, chat.completions, responses.create
anthropic, Anthropic(, messages.create
api.openai.com, api.anthropic.com, localhost:11434
OPENAI_API_KEY, ANTHROPIC_API_KEY
```

Running exactly that across four AI-adjacent repos here (`instinct-dash`,
`multitool`, `strix-halo-bench`, `octant-private`) returns **zero source hits**.

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

> **If the SDK patterns above return nothing, search by wire protocol instead:
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

### 2.4 HIGH: The Linux NPU row is wrong (confirmed)

Step 2's profile table lists:

| App's primary need | Default model | Recipe |
|---|---|---|
| Speech-to-text (Linux NPU) | `whisper-v3-turbo-FLM` | `flm` |

On this box (an XDNA NPU on Linux, the exact target), NPU ASR works, but not as
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
*hardware* requirement this machine meets (a Ryzen AI MAX+ PRO 395 with an
XDNA 2 NPU), while the actual blocker is that `system-info` reports
`amd_npu.family: ""` on Linux, so the device check cannot pass regardless of the
hardware. A user with the exact NPU the message asks for is told they do not
have it.

*The wrong row is removed in the PR.* Two things are left for AMD:

1. **The `flm:npu` message should name the real gate.** "Requires Windows"
   would be accurate and would cost one string; as written it sends a user
   with correct hardware to look for a hardware problem.
2. **Linux NPU ASR does work outside lemond.** It runs as a standalone
   FastFlowLM host process (`flm serve qwen3-tk:4b --embed 1 --asr 1`, `:52625`)
   serving `/v1/chat/completions`, `/v1/embeddings`, and
   `/v1/audio/transcriptions` from one process that owns the single AMDXDNA
   context. That has a real architectural consequence for *this* skill: a
   standalone process is not something the Step 4 launcher supervises, so the
   whole spawn/health/shutdown lifecycle the skill builds does not cover it.
   Either the skill says Linux NPU is out of scope, or it needs a second
   supervision path.

### 2.5 HIGH: No platform preflight: the skill ships to unknown hosts and never says the host is a variable

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
entirely **platform-unaware**. Everything lives at Lemonade's abstraction, and
the machine underneath is assumed correct.

**Why this belongs in *this* skill's scope specifically.** It is the one skill
that ships inference onto a machine the developer will never see. A
system-wide-server user can be told to fix their own host; an app's end user
cannot.

#### The gap matters because these are silent failures: the skill's own theme

The best thing about this skill is that it hunts failures which return success.
There is an entire class of those *below* Lemonade, and they present with the
same symptoms the skill teaches you to diagnose differently. From tuning notes
for this hardware:

> "Failure is SILENT and looks like success. With the HIP libs unreachable,
> `libggml-hip.so` simply never loads and llama.cpp falls back to CPU. Exit
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

`GET /api/v1/system-info`: invoked eleven times across these skills, always to
read `recipes[].backends[].state`, also returns the platform:

```json
"amd_gpu": [{ "available": true, "family": "gfx1151", "integrated": true,
              "virtual_mem_gb": 124.0, "vram_gb": 0.5 }]
```

`virtual_mem_gb` and `vram_gb` are the GTT ceiling and the BIOS framebuffer. A
misconfigured host shows different numbers. Reading `devices` alongside
`recipes` costs nothing and catches a real class of problem.

One caveat on `vram_gb`, visible in the embeddable binary's own startup log:

```
[Info] (ModelManager) Backend availability:
[Info] (ModelManager)   - NPU hardware: Yes
[Info] (ModelManager)   - System RAM: 125.1 GB (max model size: 100.1 GB)
[Info] (ModelManager)   - Largest memory pool: 0.5
[Info] (ModelManager)   - NVIDIA GPU: detection error: No NVIDIA discrete GPU found
```

"Largest memory pool: 0.5" is `vram_gb` again. On a machine with 124 GB of
GTT-backed unified memory. Lemonade's own sizing logic consumes that field, so an
app that builds a preflight on it inherits the same wrong number; pair it with
`virtual_mem_gb` or the reading is meaningless on an APU. Separately, the NVIDIA
line is logged at `Info` on an AMD-only machine. Any app that surfaces lemond's
log to users will field support tickets for a non-error.

It is only a partial preflight. Kernel version, firmware version, and IOMMU
state are not exposed, which is worth saying plainly rather than implying the
check is complete.

**Suggested fix**, deliberately small:

1. Add a **Prerequisites** section. Even three lines: the host needs a working
   GPU driver stack; a backend reporting `installed` does not mean it is
   *functioning*; on Linux, rootless containers need `crun` and
   `--group-add keep-groups` for `/dev/kfd` access.
2. In Step 3's `system-info` probe, read `devices` as well as `recipes`, and log
   the resolved device. It becomes the first line of any support conversation.
3. Add one Step 7 recovery row:

| Symptom | Cause | Recovery |
|---|---|---|
| Inference works but is dramatically slower than expected | Backend installed but not actually engaged. The runtime silently fell back to CPU | Confirm the GPU is in use (`gpu_busy_percent`, backend logs). A green `system-info` state and a successful `rocminfo` both still permit a silent CPU fallback |

#### A caveat worth stating to AMD

Most of the specific values above are genuinely out of scope here, and the
source material contradicts itself badly. `amd_iommu=off` vs `iommu=pt` *within
one repository*, two different GTT ceilings, host reserve of 4 GiB vs 12 GiB,
`ttm.pages_limit` raise-vs-lower, `--mlock` documented unusable yet shipped in
live configs. That is not an argument for omitting the topic. It is an argument
that **AMD is the only party who can state it authoritatively**, and that it
deserves its own home. See §3.3.

### 2.5b MEDIUM. The one-app-one-server assumption is never stated

Each app spawns a private `lemond` on a random port with a fresh API key. Clean
and correct for a single desktop app. What happens when that breaks is not
stated, and it breaks easily:

- Two apps built with this skill on one machine → two lemond processes, two
  model caches (or a shared one, depending on `models_dir`), two copies of the
  same weights competing for one GPU.
- An app built this way on a machine that *already* runs a system-wide Lemonade
 . The skill routes that away for the initial choice, but says nothing about
  coexistence.

The `models_dir` guidance frames `./models` purely as a privacy choice, not as a
disk-and-VRAM cost. Two apps each bundling a 4B model is ~5 GB duplicated and
two model loads competing for one GPU.

**Suggested fix.** A subsection under Step 3's bundle decisions:

> **If more than one app on the machine may do this,** weigh `models_dir: auto`
> (shared cache. Deduplicated weights, some coupling between apps) against
> `./models` (private, duplicated). Two lemond instances still compete for the
> same GPU regardless of cache choice; there is no cross-process arbitration.

### 2.6 MEDIUM: No concurrency or slot model

Related but distinct: even within one app, nothing says what happens when two
requests arrive at once, or when the app uses more than one modality.

Lemonade keeps separate slots per model class. Embedding, transcription, tts,
reranking, image, llm, and loading one does **not** evict another. That is a
genuinely useful property for this audience: an app doing
transcribe-then-summarise can keep both resident. But memory adds up, and the
"pick one default profile, do not ship a buffet" advice reads as if only one
model is ever loaded.

**Suggested fix.** A sentence in Step 2: models of different classes stay
coresident rather than evicting each other, so a multi-modality app should size
memory for the sum, not the max. Turns an unstated risk into a stated design
input.

### 2.7 MEDIUM: Version currency (partly verified)

Examples reference `v10.8.0`; live is 11.5.2. Checked here and **holding**:
`GET /api/v1/system-info` field names (the recipe/backend
`installed` / `installable` probe the skill leans on), `POST /api/v1/pull`
behaviour, and `GET /api/v1/models`. Still **unverified**: `POST /api/v1/install`
body shape, and the Step 2 model IDs beyond the ones I exercised.

The skill is already appropriately humble about `/api/v1/load` changing shape
between releases, and that humility was earned, since it did change. The same
caution should extend to the endpoints it does tell you to call.

**Suggested fix.** State a tested-against version range. Since the skill
instructs the reader to fetch the *latest* release, a note that model IDs and
`system-info` fields should be confirmed against the version actually downloaded
would be consistent with its own `server_models.json` guidance.

### 2.8 LOW: "~30 lines and three changes" undersells the work **[unverified]**

The opening promises one ~30-line launcher, three client changes, one vendored
binary. The body then requires per-stage logging, a loading indicator covering
the whole cold-start sequence, bypassing every API-key gate, a first-run backend
install, a pull step, shutdown handling, and watcher exclusions. The
verification checklist has eleven boxes.

All justified, but a reader who budgets against the headline will be surprised,
and the risk is abandonment halfway, leaving exactly the half-configured state
the skill warns about.

**Suggested fix.** Keep the headline for the *core* change and add a clause:
"…plus first-run setup (backend install, model pull), progress UI, and lifecycle
handling. Budget a day for a first integration." Honest scoping makes the skill
more likely to be finished, not less likely to be started.

### 2.9 to 2.10 LOW. Two wording fixes, both in the PR

- **Step 1 numbering.** "Record three things before continuing" is followed by a
  four-item list; the fourth (API-key gating) is load-bearing and should be
  counted.
- **Shutdown guidance.** "`proc.terminate()` (Unix) or `proc.kill()` (Windows)"
  reads as though Windows requires the harsher call. On POSIX `terminate()` is
  SIGTERM and `kill()` is SIGKILL; on Windows Python maps both to
  `TerminateProcess`, so they are the same call. Now written as terminate →
  `wait(timeout=5)` → kill, which is what the skill's own "lemond flushes config
  and exits cleanly within a couple of seconds" implies.

### 2.11 HIGH: Nothing in the skill can conclude "do not integrate" (confirmed against a real host)

Step 1 asks whether the app calls cloud AI, and if it does, every later step
assumes the swap should happen. No step asks the prior question: **can Lemonade
supply what the app's current inference path already supplies?**

Run against a real host, the answer can be no. `thewh1teagle/vibe` is about as
close to this skill's ideal host as public code gets. An MIT Tauri v2 desktop
transcription app that already vendors an OpenAI-compatible local inference
sidecar (`sona`) as an `externalBin`, spawns it as a subprocess, and talks to it
over HTTP. §3.5 records the full swap analysis; the conclusion is that the swap
should not ship. Four independent mismatches, none of them fixable in
integration code, and **each discoverable in minutes before any code is
written**:

| Mismatch | Cheap check that finds it first | Section |
|---|---|---|
| `stream=true` on `/api/v1/audio/transcriptions` is accepted and silently ignored | one timed request. Measure time to first *body* byte | §2.17 |
| No `speaker` field in any response format. No diarization | one request, `grep -i speaker` | §3.5 |
| `GLIBC_2.38` / `GLIBCXX_3.4.32` floor in the binary you vendor | `objdump -T lemond` | §2.15 |
| Config mutation, shared model cache, LAN broadcast | read the startup log once | §2.13, §2.14 |

The cost of not having that gate is not a bad integration. It is a *finished*
integration that ships a product with fewer features than it had, discovered
after Steps 3 to 5 are done and the packaging is rebuilt.

**Suggested fix. A Step 0, before the survey.** Below is literal drop-in text,
formatted to match the existing Steps 1 to 7 exactly, so it can be pasted into
`SKILL.md` rather than re-derived. Two edits are needed: renumber the
opinionated-path checklist, and insert the new step ahead of Step 1.

*Opinionated-path checklist (top of `SKILL.md`) becomes:*

```
[ ] 0. Confirm Lemonade can supply what the app already has
[ ] 1. Survey the app's current AI integration
[ ] 2. Pick a model + backend profile
[ ] 3. Place Embeddable Lemonade in the app's tree (full package, not just the binary)
[ ] 4. Add a `lemond` launcher (subprocess + API key + port + per-stage logging)
[ ] 5. Re-point the existing client at lemond (base_url, api_key, 120s timeout, all three required)
[ ] 6. Wait for /api/v1/health, install backend, then PULL the model before first use
[ ] 7. Wire shutdown and error recovery
```

*New section, inserted immediately before "## Step 1: Survey the app":*

~~~markdown
## Step 0: Confirm Lemonade can supply what the app already has

Before vendoring anything, exercise the endpoint the app will actually use
against **any** running Lemonade instance. A system-wide install is fine for
this step; you do not need the embeddable binary yet. Check four things.
**"Do not integrate" and "integrate the batch path only" are legitimate
outcomes of this step**, not failures of the process. Deciding not to swap
is cheaper here than after Steps 3 to 5 are built.

1. **Streaming.** If the app's current path streams (SSE, NDJSON, chunked
   transfer), time the Lemonade equivalent's *first body byte*, not its
   headers:

   ```bash
   time curl -N -X POST http://127.0.0.1:{port}/api/v1/<endpoint> \
     -d '{"stream": true, ... }'
   ```

   A request accepting `stream=true` is not evidence that it streams. Some
   Lemonade endpoints accept the parameter and return the entire body at once
   regardless. If time-to-first-byte and time-to-last-byte are within noise
   of each other, treat the endpoint as non-streaming: any progress bar or
   incremental render the app currently drives from partial output will
   degrade to an indeterminate spinner.

2. **Response fields.** Call the endpoint once and diff the response body
   against every field the app reads today. Not just the fields a client
   SDK's types declare, since a hand-rolled HTTP client may read the raw JSON
   directly (see Step 1's note on hand-rolled clients). A field the app
   currently renders that Lemonade's response does not carry (e.g. a speaker
   or diarization label) is a **feature lost**, not a mapping problem to
   solve later in integration code.

3. **ABI floor** (Linux, only if vendoring the embeddable binary in Step 3).
   Check the binary's glibc floor against the oldest distro the app packages
   for:

   ```bash
   objdump -T lemond | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1
   ldd --version | head -1   # glibc on each target distro/container
   ```

   A floor above your oldest supported distro's glibc is a packaging-breaking
   defect that surfaces at runtime on the user's machine, not at install time
   on yours.

4. **Side effects.** Start `lemond` once with the config you intend to ship,
   and read the first few seconds of its stdout for: any listening socket
   beyond the one port you chose, any config file written outside the
   directory you expected, and any network broadcast/discovery traffic. A
   packaged app inherits each of these silently unless you configure it away.

**Decide before continuing to Step 1:**

| What you found | Outcome |
|---|---|
| No losses, no unacceptable side effects | Continue to Step 1 |
| A loss exists, but the app doesn't use that capability today | Continue; note the gap in Step 2's profile choice |
| A loss exists and the app **uses** that capability today | Do not integrate that mode. Scope the integration to exclude it (e.g. "batch transcription only, no live/streaming UI"), or do not integrate at all |

Record the decision and its reason. A scoped-down or declined integration is a
correct output of this skill, not an incomplete one.
~~~

This is a gap in the guide, not a verdict on Lemonade. For a host without a
live transcript or speaker labels the same swap is straightforwardly feasible.
The problem is that the skill is written as a one-way procedure with no exit, so
an agent following it produces a swap whether or not the swap is an improvement.

### 2.12 HIGH: `health` 200 precedes model-cache-ready, and there is no machine-readable ready signal (confirmed)

Step 4 is unambiguous:

> Poll `GET /api/v1/health` … until HTTP 200. **this is the only correct
> readiness check.**

Measured on the embeddable binary, it is not the last gate. lemond's stdout is
human-readable log text with no structured ready line:

```
2026-08-13 11:29:05.991 [Info] (main) Starting Lemonade Server...
2026-08-13 11:29:05.993 [Info] (Server) Starting HTTP server on 127.0.0.1:13399
2026-08-13 11:29:05.994 [Info] (ModelManager) Building models cache...
2026-08-13 11:29:05.998 [Info] (Server) IPv4 HTTP server listening on 127.0.0.1:13399
2026-08-13 11:29:07.128 [Info] (ModelManager) Cache built: 132 total, 13 downloaded
```

**Health returned 200 at ~1 s after spawn; the model cache finished building at
~1.14 s.** A ~140 ms window on this machine, but an app that does exactly what
Step 4 says (poll health, then `GET /api/v1/models` to choose a model) can
observe an empty or partial catalog inside it. The window scales with catalog
size and a cold page cache, and it presents as "the model list came back empty",
which Step 7's recovery table attributes to an unpulled model.

Two related findings from the same measurement:

- **No `--port 0` ephemeral mode** is advertised in `--help`, so the Step 4
  launcher's bind-to-0-then-close trick is the only option. A TOCTOU race the
  reference launcher can only paper over with retries.
- **A real desktop host already expects better.** Vibe's sidecar prints
  `{"status":"ready","port":N}` as the first line of stdout, and
  `SonaProcess::spawn` blocks reading exactly that one line
  (`desktop/src-tauri/src/sona/process.rs`). Replacing that sidecar with lemond
  means replacing a deterministic handshake with a poll plus a heuristic.

**Suggested fix.** Extend §1.1's own sequence by one stage and make the readiness
check compound:

```
server spawn → health 200 → model cache built → backend install → model download → model load → first result
```

i.e. ready means health 200 **and** `GET /api/v1/models` returning a non-empty
list. That is two lines in the reference launcher.

**Worth AMD's consideration:** one structured line on stdout after the cache is
built, or a `--ready-fd`: removes the race and the log-scraping at once, and
would let embeddable `lemond` drop straight into the Tauri `externalBin` slot
that competing sidecars already occupy.

### 2.13 HIGH: The private-instance framing does not hold: the cache directory does not isolate models, and `--port` rewrites `config.json` (confirmed)

Step 4 spawns
`[LEMOND_BIN, LEMOND_DIR, "--port", str(port)]`. Both of those arguments behave
differently from what the surrounding prose implies.

**`LEMOND_DIR` does not isolate anything.** `--help` describes the positional as
"Lemonade cache directory containing config.json **and model data**". Started
against a brand-new empty directory:

```
$ ./lemond --port 13399 --host 127.0.0.1 <fresh-empty-dir>
[Info] (ModelManager) Cache built: 132 total, 13 downloaded
$ curl -s 127.0.0.1:13399/api/v1/models | ...
listed: 13   whisper entries: ['Whisper-Large-v3-Turbo', 'Whisper-Tiny']
```

The fresh directory ended up holding exactly `config.json` and an empty `bin/`.
The 13 models came from the user's **shared Hugging Face cache**, because
`models_dir` defaults to `"auto"`. The skill does mention `models_dir`, but in
Step 3, as a *privacy preference* ("leave as `auto` only if the user explicitly
wants to share weights"), far from the Step 4 launcher that makes the directory
argument look like the isolation boundary. It is not one. Without an explicit
`models_dir`, an embedded instance reads models it never downloaded, contends
with the user's own Lemonade install for them, and leaves weights behind on
uninstall. §2.5b argues that the shared-cache choice deserves to be a stated
trade-off; this is the stronger version of the same point. The trade-off is
currently made *for* the reader, by a default, in the direction the Step 4
launcher makes look impossible.

**`--port` and `--host` are persisted, not overridden:**

```
[Info] (main) Persisted port=13399 to config.json
[Info] (main) Persisted host=127.0.0.1 to config.json
```

`reference.md` says of the `port` config key: "Override at launch with `--port`
instead", which reads as ephemeral. It is not. The Step 4 launcher picks a fresh
random free port **every launch**, so every launch rewrites `config.json`, which
is exactly the file churn §1.8's watcher hazard is about. The skill's own port
strategy guarantees the write its watcher warning tells you to avoid.

**Suggested fix.** SKILL.md's layout block calls `config.json` "generated on
first run; commit a seed copy". Make the seed mandatory and non-empty, and move
`reference.md`'s "Recommended embedded defaults" block into Step 3. `models_dir`,
`no_broadcast` and `host` all have to be set *before* first launch, not observed
after it.

**Worth AMD's consideration:** the `--help` text for the positional argument is
wrong and should be fixed at the source; and `--port`/`--host` should either be
documented as persisting or made genuinely ephemeral. A dynamically-ported
embedded server is the flagship use case for that flag.

### 2.14 MEDIUM: Two network surfaces the skill never mentions: a second listener, and LAN broadcast from a loopback-bound server (confirmed)

`--port` controls one of **two** listening sockets. The embedded instance also
opened a WebSocket listener:

```
[Info] (WebSocket) Configured port: 9001
[Info] (Server) WebSocket server started on port 9001
```

confirmed with `ss`:

```
127.0.0.1:9001   lemond pid=291962   (embedded)
127.0.0.1:13399  lemond pid=291962   (embedded)
127.0.0.1:13305  lemond pid=2336     (system)
```

The system instance holds 9000 and the embedded one selected 9001, so collision
avoidance works. But this is a socket the launcher does not choose, cannot
report, and does not know exists. It matters for firewall prompts, flatpak/snap
sandbox manifests, endpoint-security agents, and port budgeting. Neither
`SKILL.md` nor `reference.md` contains the strings `websocket`, `9000`, or
`9001`.

Second, with `--host 127.0.0.1` and a default config:

```
[Server] [Net Broadcast] Broadcasting on 5 RFC1918 interface(s):
  127.0.0.1 (bcast 255.255.255.255) 192.168.252.24 (bcast 192.168.252.255)
  192.168.122.1 172.17.0.1 172.18.0.1
```

Binding to loopback does not suppress the discovery beacon. It went out on the
LAN and on the docker and libvirt bridges. **The payload is worse than "a
broadcast happened".** Captured with `tcpdump` on the LAN bridge and decoded:

```
192.168.252.24.44552 > 192.168.252.255.13305: UDP, length 91
  {"service": "lemonade", "hostname": "barlow", "url": "http://192.168.252.24:13406/api/v1/"}
```

Sent every 2 seconds to the fixed well-known port `13305`: not the
instance's own port. With the payload carrying the actual host, machine
name, and LAN-reachable URL of *that specific instance* (port `13406` in this
capture). Bound to `127.0.0.1` with no auth configured beyond
`LEMONADE_API_KEY`, the embedded instance still announces its real network
address and hostname to anything listening on the LAN.

`reference.md` does carry the mitigation (`no_broadcast`, "**Set `true` for
embedded apps**, disables UDP discovery beacon"), but only as a row in a
config table plus a line in a recommended-defaults block that `SKILL.md` never
tells the reader to apply, and the default is on. An app built exactly as the
skill describes broadcasts its hostname and reachable URL from every RFC1918
interface without its developer being told. That is a finding that surfaces in
a customer security review rather than in testing.

**Verified the mitigation actually works, at the packet level, not just the
log level.** Set `no_broadcast: true` in `config.json`, then captured on the
same bridge for the full run: `lemond` logs
`Broadcasting disabled by --no-broadcast option`, and zero packets referencing
the instance's port appeared on the wire (only the unrelated system instance's
own beacon to `13305`, running independently, was visible). `no_broadcast`
is a real, effective off switch. The gap is that it defaults to on and the
skill never tells the reader to set it.

**Suggested fix.** Name the second port in Step 4's launcher description, and
promote `no_broadcast: true` out of the reference table into the Step 3 seed
config with its reason attached.

### 2.15 HIGH: The vendored binary has an undocumented glibc floor that excludes currently-supported distros (confirmed)

The skill tells the reader to download and ship `lemond` and says nothing about
what it links against. Measured on the artifact named in the header:

```
$ objdump -T lemond | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1
GLIBC_2.38
$ objdump -T lemond | grep -oE 'GLIBCXX_[0-9.]+' | sort -uV | tail -1
GLIBCXX_3.4.32
```

Dynamic dependencies: `libz`, `libzstd`, `libssl.so.3`, `libcrypto.so.3`,
`libdrm_amdgpu.so.1`, `libdrm.so.2`, `libstdc++.so.6`, `libm`, `libgcc_s`,
`libc`.

`GLIBC_2.38` is a hard floor. All four rows below are now **measured**: each
distro's official Docker image, with `libssl3`/`libdrm2`/`libdrm-amdgpu1`
installed (the artifact's own dynamic deps) so the only variable is glibc,
running the extracted binary directly (`docker run -v ... lemond --help`):

| Distro | glibc | Runs? |
|---|---|---|
| Ubuntu 24.04 LTS | 2.39 | **yes**: measured |
| Ubuntu 22.04 LTS (supported to 2027) | 2.35 | **no**: measured |
| Debian 13 trixie | 2.41 | **yes**: measured |
| Debian 12 bookworm | 2.36 | **no**: measured |

The two failing distros produce the identical dynamic-linker error, before any
`lemond` log output:

```
/lemond/lemond: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found (required by /lemond/lemond)
/lemond/lemond: /lib/x86_64-linux-gnu/libstdc++.so.6: version `GLIBCXX_3.4.32' not found (required by /lemond/lemond)
```

exit code 1. This is not a soft degradation. The process never starts, so
none of the skill's own diagnostics (health check, logging) ever run. A
`.deb`/AppImage built from this artifact with no glibc floor in its metadata
installs cleanly on Ubuntu 22.04 or Debian 12 and fails only at first launch.

This is a distribution-blocking property of the exact artifact this skill tells
you to produce. A `.deb` or AppImage carrying no glibc floor in its metadata
installs cleanly on Ubuntu 22.04 and then fails at first launch with a
dynamic-linker error. Silent until runtime, which is the skill's own genre of
failure. Lemonade's release workflow carries a comment stating the deps are
FetchContent-static "so the embeddable binary is portable across Ubuntu
versions"; measured, it is not.

Smaller, same neighbourhood: the archive's `resources/` holds **six** JSON files
,  `server_models.json`, `backend_versions.json`, `defaults.json`,
`vllm_model_config.json`, `bench_scenarios.json`, `toolDefinitions.json`: and
Step 3's layout block shows two. Cosmetic beside the ABI floor, except that §1.7
exists specifically to warn about incomplete copies of that directory, so the
list should be right or explicitly marked non-exhaustive.

**Suggested fix.** State the floor in Step 3 together with the command to
re-check it against whatever release the reader actually downloads. The skill
tells them to fetch *latest*, so the number will drift, and add a packaging
line: set the glibc dependency in `.deb` control metadata, build AppImages
against the oldest supported base, or document the minimum distro.

**Worth AMD's consideration:** publishing the floor in the embeddable release
notes, or building the Linux embeddable artifact against an older base, fixes
this once for every downstream app instead of once per integrator.

### 2.16 LOW: No fetchable OpenAPI document (confirmed)

`/docs` and `/redoc` return 200 HTML, but it is the SPA shell; `/openapi`
returns the same. `/openapi.json`, `/api/v1/openapi.json`, `/swagger.json`,
`/api/openapi.json` and `/v1/openapi.json` all 404. There is no machine-readable
spec, so an integrator cannot codegen a client or introspect request shapes and
must work from prose, which is how §2.1 and §2.2 survived into a shipped skill.
(Linux embeddable builds set `BUILD_WEB_APP=OFF`, so the bundled UI is absent
there in any case.)

Incidentally this confirms the 404-discrimination rule the skill uses in Step 7:
`/openapi.json` 404s as `text/plain` "File not found" from the static handler,
while `/api/v1/openapi.json` 404s as `application/json` from the API router.

**Worth AMD's consideration:** serving the OpenAPI document is the cheapest
available fix for a whole class of doc-drift defects, this review included.

### 2.17 MEDIUM: `/api/v1/audio/transcriptions` diverges from OpenAI in three ways, all silent (confirmed)

`reference.md` describes the route as "OpenAI Whisper-style transcription".
Measured at 11.5.2 with `whispercpp:vulkan` and `Whisper-Large-v3-Turbo` on a
371.6 s audio file.

**1. `stream=true` is accepted and ignored.**

| | `stream=true` | `stream=false` |
|---|---|---|
| Content-Type | `application/json` | `application/json` |
| Top-level keys | `['text']` | `['text']` |
| Time to first byte | 0.00047 s (headers only) | 0.00045 s |
| Time to body | 12.36 s | 11.42 s |

No SSE, no NDJSON, no chunked incremental delivery. The whole body lands at the
end, and nothing in the response says the parameter was dropped. Note that the
server's own log line `BackendWatchdog … (streaming=on, non_streaming=on)`
describes the *backend's* capability, not the HTTP surface, so an integrator
reading the log reasonably concludes streaming is available.

**2. `response_format=srt` and `=vtt` return correct payloads wrapped in a JSON
envelope:**

```
srt  → {"text":"1\n00:00:00,000 --> 00:00:29,980\n Thank you.\n\n"}
vtt  → {"text":"WEBVTT\n\n00:00:00.000 --> 00:00:29.980\n Thank you.\n\n"}
```

OpenAI returns both as raw `text/plain`. Any OpenAI-compatible client that writes
the response body straight to a `.srt` file. The obvious thing to do: produces
a JSON blob with escaped newlines instead of a subtitle file.

**3. `json` and `text` are indistinguishable**: both return `{"text": …}`,
where OpenAI's `text` returns a bare string.

`verbose_json`, by contrast, is *richer* than OpenAI: 92 segments on the test
file with `avg_logprob`, `no_speech_prob`, `temperature`, `tokens` and populated
per-word timestamps (`{start, end, probability, t_dtw, word}`), plus
`detected_language`, `detected_language_probability`, `duration` and `task` at
top level.

**Suggested fix (skill).** Step 5's client table presents the surface as
uniformly OpenAI-compatible. It should name, per modality, which OpenAI features
do not carry over. Streaming transcription being the concrete one, since an app
that streams today loses a shipped feature (§3.5).

**Worth AMD's consideration:** 2 and 3 are small self-contained conformance fixes
,  return the payload as `text/plain` for `srt`, `vtt` and `text`. 1 is a larger
decision, but accepting a parameter and silently not honouring it is the worst of
the available options; rejecting `stream=true` with a 400 would be strictly
better than ignoring it.

---

## 3. Candidate hosts and a catalog gap

### 3.1 `judge.py` is the ideal first integration host

Beyond being the §2.3 example, `judge.py` satisfies Step 1's hardest requirement
out of the box:

> **One single place** where the base URL and API key are constructed. If there
> isn't one, refactor to one before going further.

It already has that. `_resolve_backend()` returns an `(kind, model, endpoint,
headers)` tuple selected by a backend string, and it already has a `local:`
option pointing at a local CCR. Adding a `lemonade:` selector is close to the
minimal possible version of this integration, which makes it a good control: if
the "three changes" claim holds anywhere, it holds here. It also exercises §2.1
directly, since the judge speaks Anthropic Messages.

**Tested. It works, and the "three changes" claim broadly holds.** A
`lemonade:<model>` selector alongside the existing `none` / `local:` /
`gateway:` came to **+40 lines**, all additive, and returned a parseable verdict
with a correctly written sidecar on the first run. Against the three prescribed
changes:

| change | outcome |
|---|---|
| `base_url` | needed, but **not the documented value** (§2.1) |
| `api_key` | needed, inverted: loopback lemond is unauthenticated, so the right move was to send a key *only if* `LEMONADE_API_KEY` is set, rather than always |
| 120 s timeout | **already satisfied**: the client's `JUDGE_TIMEOUT_S` happened to default to exactly 120 |

Two qualifications. This was the easiest possible host. It already had the
single config point Step 1 demands *and* a pluggable-backend abstraction; an app
with neither would pay the refactor the skill mentions only in passing. And the
`api_key` row suggests the skill's framing assumes its own Step 4 launcher, which
mints a per-launch key; a system-wide server has no key at all, and the skill's
"set `api_key` to the launcher key" has no counterpart there.

Caveat: it is a batch harness, not a desktop app, so it did not exercise the
progress-UI or key-gating requirements, nor Steps 3 to 4 (vendoring, subprocess
launcher). This validates **Step 5 only**. `instinct-dash` (Fastify + React + Vite,
Playwright harness) is the secondary host for those, and is the right instrument
for the §1.8 watcher hazard since Vite is precisely the case that warns about.

### 3.2 The gap: one server, many networked consumers

Between the two local-AI skills:

- `local-ai-use` → one workspace, one agent, system-wide server.
- `local-ai-app-integration` → one app, one private embedded server.

Neither covers **one Lemonade instance, many consumers over a network**: a
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

This is the natural fourth skill, and the catalog's most defensible gap. Every
other skill in this family assumes its output. It is also the one topic where
AMD's authority is decisive: a community author guessing at
`amdgpu.gttsize` values will get them wrong, and the existing published guidance
already disagrees with itself.

Together with §3.2 (one server, many networked consumers) that is two catalog
gaps, both sitting *underneath* rather than beside the current skills.

### 3.4 The pattern this skill teaches has no public demonstration

Lemonade's own docs carry twelve integration guides. `ai-toolkit`,
`anythingLLM`, `claude-code`, `codeGPT`, `continue`, `langchain`, `lemon-zest`,
`mindcraft`, `open-hands`, `open-webui`, `pi`, `wut`. **Every one of them is
config-level**: point an existing app's OpenAI base URL at a running Lemonade.

Meanwhile `docs/embeddable/` documents the vendored-`lemond` flow thoroughly , 
release artifacts per platform, `server_models.json` and `backend_versions.json`
customisation, the deployment-ready layout, and ships **no reference app**.

So the easy case has twelve worked examples and the case this skill exists to
teach has zero. That asymmetry explains several things at once:

- Why §2.8's "~30 lines and three changes" headline is optimistic: the twelve
  guides really *are* that easy, and the framing appears to have carried over
  from them to a job that is much larger.
- Why the `@anthropic-ai/sdk` base_url (§2.1) survived to review: a config-level
  guide is verified by the app working, and none of the twelve uses that SDK.
- Why §2.5's platform-preflight gap is invisible from inside AMD: every
  documented integration runs against a Lemonade the *user already installed and
  proved working*. This skill is the only one that ships onto an unproven host.

**Suggested fix. A reference app, not more prose.** One small, real desktop app
that vendors embeddable `lemond`, spawns it, shows cold-start progress, and shuts
it down. It would make the skill checkable, give the twelve config-level guides a
counterpart, and pin the version drift the rest of §2.7 asks about.

The candidate was [`thewh1teagle/vibe`](https://github.com/thewh1teagle/vibe): a
Tauri transcription app whose `tauri.conf.json` already declares
`"externalBin": ["binaries/sona"]`. It is the same shape the skill prescribes
(desktop app supervising a vendored inference binary), so substituting embeddable
`lemond` for the existing sidecar tests Steps 3 to 4 as a swap rather than a
greenfield build, on the exact stack §1.8's watcher warning names. **The swap was
analysed and rejected; §3.5 records why, and that outcome is itself the most
useful thing this review produced.**

### 3.5 The Vibe swap: a worked case for *not* integrating

`thewh1teagle/vibe` (MIT, Tauri v2, app version 3.0.23, surveyed at `1c5466b`)
is as close to this skill's ideal host as public code gets: a desktop
transcription app that already vendors an OpenAI-compatible local inference
server (`sona`, MIT, pinned by `.sona-version`) as a Tauri `externalBin`, spawns
it as a plain `std::process::Command` subprocess, and drives it over HTTP.
Substituting embeddable `lemond` is a like-for-like exchange of one local
inference server for another.

**The seam is clean and small.** `SonaProcess`
(`desktop/src-tauri/src/sona/process.rs`, `sona/mod.rs:139`) is the *only*
transcription implementation. No `whisper-rs`, no `vibe_core`, no
`pyannote-rs` remain in `Cargo.lock`, and all three user entry points (home,
batch, hotkey dictation) converge on one `transcribe` Tauri command. Everything
above that line is backend-agnostic. A lemond-backed implementation has to
satisfy three HTTP calls, one CLI call (`sona devices` → JSON GPU list), and one
stdout ready handshake. On the skill's own terms this should be the easy case.

**It should not ship.** Four independent grounds, none of them an
integration-code problem:

1. **Streaming is lost (§2.17).** `transcribe_stream` reads NDJSON and emits
   `progress` and `segment` events into the UI as they arrive; the frontend
   renders a live transcript and drives a taskbar progress bar from them.
   Lemonade delivers nothing for 12 s and then everything, and `stream=true`
   does not change that. There is no signal to compute a percentage from, so the
   honest port is a spinner: two shipped features collapse into one
   indeterminate one.
2. **Diarization is lost.** Vibe's `Segment` is `{start, stop, text, speaker}`.
   `grep -i speaker` over the full Lemonade response matches nothing, in any
   `response_format`. This is the larger regression and it is structural: Vibe
   deleted `pyannote-rs` *because* sona diarizes in-process. Swapping to
   Lemonade means shipping a diarization-free build or re-adding a separate
   diarization stage the app had already retired.
3. **The distribution matrix shrinks (§2.15).** Vibe ships a `.deb` today with a
   system `ffmpeg` dependency and no glibc floor. Vendoring this binary breaks
   Ubuntu 22.04 LTS and Debian 12 users at runtime, not at install time.
4. **The side effects are wrong for a packaged app (§2.13, §2.14).**
   `config.json` rewritten on every launch, the user's global HF cache shared
   rather than isolated, and UDP broadcast on every RFC1918 interface. All are
   mitigable; none is mentioned where the reader will hit them; and all three
   are properties this app had already got right with its existing sidecar.

The field mapping. The part the skill *does* prepare you for: is trivial by
comparison: `start`/`stop` in centiseconds against Lemonade's `start`/`end` in
float seconds (a rename and a ×100), `text` direct, and strictly more
per-segment data returned than Vibe consumes.

**The point is about the guide, not the backend.** For a batch or offline
transcription tool with no live transcript and no speaker labels, this swap is
straightforwardly feasible: the ABI floor is satisfied on a current distro, the
artifact is Apache-2.0 and carries its LICENSE, `whispercpp:vulkan` can be staged
offline on Linux, and `verbose_json` returns more than Vibe uses. The skill has
no step at which those two cases are distinguished. A Step 0 (§2.11) reaches
"do not integrate, or integrate the batch path only, behind a setting" in under
an hour, before any vendoring, launcher, or packaging work. Without one, the
procedure runs to completion and delivers a downgrade.

---

## 4. Testing performed

| # | Test | Status | Settles |
|---|---|---|---|
| T1 | Namespace/endpoint sweep at 11.5.2 across all three namespaces | **done**; `messages` is `/v1`-only, rerank is `reranking`, everything else aliases | §2.1, §2.2 |
| T2 | `lemonade:` backend for `judge.py`: a real Anthropic-Messages client | **done**; +40 lines, all additive; §2.1 reproduced end-to-end as a negative control | §2.1, §2.8, §3.1 |
| T3 | `lemonade backends install {whispercpp,ryzenai-llm,flm}:npu` on Linux | **done**; all three refuse, exact strings in §2.4 | §2.4 |
| T4 | Skip the pull step; check whether empty-200 reproduces at 11.5.2 | **done**; it does not. First inference blocks and downloads instead | §1.2, §2.0 |
| T5 | *(folded into T1)* | done | §2.2 |
| T6 | Full vendored integration into a watcher-driven desktop host: Steps 3 to 4 end to end (vendoring, launcher, shutdown), progress UI, key gating, `vendor/` left in the watched tree | **not run**: deliberately, see below | §1.8, §2.8, progress UI |
| T7 | Embeddable artifact: download, checksum, extract, run standalone on `:13399` beside the system instance | **done**; readiness race, shared model cache, config mutation, second listener, LAN broadcast, ABI floor, no OpenAPI | §2.12 to §2.16 |
| T8 | Vibe swap survey. Locate the seam, enumerate what a lemond-backed implementation must satisfy | **done**; the seam is `SonaProcess`, everything above it is backend-agnostic | §2.11, §3.5 |
| T9 | `/api/v1/audio/transcriptions` contract measured field-by-field against Vibe's `Segment`: `stream=true`, every `response_format`, diarization | **done**; streaming ignored, no `speaker`, `srt`/`vtt` JSON-wrapped | §2.17, §3.5 |
| T10 | Run the extracted `lemond` binary inside official `ubuntu:22.04`/`debian:12`/`ubuntu:24.04`/`debian:13` Docker images (runtime deps `libssl3`/`libdrm2`/`libdrm-amdgpu1` installed, so glibc is the only variable) | **done**; the two older distros fail with an identical dynamic-linker error before any output, the two current ones run cleanly. Distro matrix moved from inferred to measured | §2.15 |
| T11 | `tcpdump` on the LAN bridge with `no_broadcast: false` (positive control) and `true`, decoding the beacon payload | **done**; payload is `{"service","hostname","url"}` sent every ~2s to fixed port 13305; `no_broadcast: true` produces zero matching packets and an explicit "disabled" log line. Mitigation confirmed at both layers | §2.14 |

**T6 is still the one real gap, but it is now a deliberate one.** It is the only
test that would exercise Steps 3 to 4 (vendoring, the subprocess launcher,
shutdown) plus the progress-UI and key-gating requirements. Everything T2 could
not reach, since `judge.py` is a batch harness with a pre-existing config point.
It is also the only way to confirm the file-watcher hazard in §1.8 rather than
taking it on trust.

**The host has been changed, and the reason is worth recording.** T6 was
originally scoped against `instinct-dash`, a local dashboard already talking to
Lemonade. On inspection it calls only `GET /api/v1/models` and `GET /health`: it
*observes* Lemonade and never consumes inference. Run the skill against it and
every step correctly no-ops: Step 1 finds no cloud AI because there is none, and
Steps 3 to 4 would be actively wrong, since embedding a private `lemond` contradicts
the purpose of a monitor for the system-wide one. Testing it would have meant
inventing an inference feature and then integrating my own demo.

That is a useful negative result about the skill's *applicability*: an app can be
thoroughly "local-AI integrated" and still be entirely out of scope here. Step 1
distinguishes has-cloud-AI from has-none, but nothing distinguishes
consumes-inference from observes-inference, and the second is common in exactly
the tooling-and-dashboard code around an inference host.

**Why T6 was not run against Vibe either.** T8 and T9 established that the
finished integration would ship a product with fewer user-visible features than
it has today (§3.5). Running T6 would have meant building and packaging an
integration in order to test a guide, knowing the result should not merge. So
the launcher, vendoring and shutdown steps remain unverified by me at the
application level. T7 covers part of the same ground from below: it tests the
*binary* those steps produce, which is where §2.12 to §2.16 came from. What is still
untested is the app-side half. Progress UI, key gating, and the watcher
interaction.

That gap has a silver lining worth stating: the reason T6 stalled twice, on two
different hosts and for two different reasons, is itself the §2.11 finding.
Neither `instinct-dash` (observes inference, does not consume it) nor Vibe
(consumes it, but needs capabilities Lemonade does not expose) is a host this
skill should be run against, and the skill has no step that would have said so
in either case.

Everything else is settled. T4 was a reproduction test of the skill's own
headline warning and came back negative, which is the most consequential result
about content the skill *has*: confirming a documented hazard is real is as
useful as finding a new one, and finding it *replaced* is more useful still. T9
is its counterpart for content the skill does not have: a measured capability
gap that no amount of correct integration code closes.

---

## 5. Summary

The best-written of the three. The organising insight, that this integration
fails silently at five distinct stages, so the job is instrumenting each
transition, is correct and applied consistently rather than stated once. The
empty-200 diagnosis, the mandatory 120s timeout with its reason, the
`resources/` warning, and the file-watcher hazard are all things a reader could
not derive from the API docs.

The reproduced defects (the `@anthropic-ai/sdk` 404, the `reranking` naming
divergence, the Linux NPU row, and the unpulled-model behaviour) are in the PR
and need no decision here.

What is left for AMD is structural, and it is one thing said three ways: the
skill models a **document** shipping to a **known** machine. §2.5 (no platform
preflight), §2.5b (one-app-one-server), and §2.6 (no concurrency or slot model)
are all the same absence. The skill is thoroughly backend-aware and entirely
platform-unaware, and it is the one skill in the family that ships inference
onto a machine its author will never see.

To that list the embeddable-binary and Vibe work adds a fourth absence, and it
is the one with the largest consequence: **the skill has no exit.** It can
decide that an app has cloud AI to replace, but not that Lemonade cannot supply
what the app already ships. Attempting a real swap into Vibe, the closest thing
to this skill's ideal host in public code, produced four independent blockers
(§3.5), every one of which a four-item pre-flight would have surfaced in minutes
(§2.11). "Do not integrate" and "integrate the batch path only" need to be
outcomes the skill can reach.

Related and cheap to fix: §2.12 to §2.16 all came from extracting the embeddable
archive and reading the first two seconds of its startup log. The readiness race,
the shared model cache, the persisted `--port`, the second listening socket, the
LAN broadcast and the `GLIBC_2.38` floor are all visible there. That none of them
appears in the skill suggests the embeddable path has been documented from its
design rather than from its behaviour. The same asymmetry §3.4 identifies from
the other direction, and the reason a reference app would pay for itself.

Step 1's survey patterns are the other actionable design gap (§2.3): they find
vendor SDKs but miss hand-rolled HTTP clients. The failure mode most likely to
make an agent decline a job it should take, and the reason a good candidate host
sitting in `strix-halo-bench` is invisible to the skill's own discovery step. I
found this by running the skill's own patterns and getting zero hits on repos I
knew contained cloud AI clients.

Separately and more strategically, the topology I actually run (one server,
many networked consumers, plenty of commercial traffic to redirect) is served
by neither this skill nor `local-ai-use` (§3.2). Worth a conversation about
catalog coverage independent of any edit here.
