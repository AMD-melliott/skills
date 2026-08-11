# Feedback — `local-ai-app-integration`

**Reviewer:** Matt Elliott
**Date:** 2026-08-11 (initial pass — desk review; integration test pending)
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy

> **Status of this document.** This is a desk review of `SKILL.md` and
> `reference.md` against a live 11.5.2 stack and a set of candidate host
> applications. Items marked **[unverified]** are hypotheses the test plan in §4
> will settle. I have **not** yet run the integration — §3.1 explains why
> finding a legitimate host application was itself a finding.

---

## 1. What works well

This is the strongest-written of the three Lemonade skills. Its core insight —
that a local integration fails *silently* in five different places and the whole
job is making those failures visible — is correct and consistently applied.

### 1.1 "health 200 ≠ ready" is the right organising principle

Step 6 states the real sequence plainly:

```
server spawn → health 200 → backend install → model download → model load → first result
```

and then says outright that "treating health=200 as 'ready' is the single
biggest cause of a broken-looking integration." Most integration guides stop at
the health check. Naming the four things that must *also* be true, and giving
each one a step, is what makes this skill worth following rather than skimming.

### 1.2 The silent-empty diagnosis

> If inference returns an empty string / blank output with no HTTP error, the
> model was not downloaded.

An unpulled model returning **HTTP 200 with a blank body** is exactly the kind of
failure that costs a day, because every instinct says to debug the client, the
prompt, or the parsing. The skill names it, gives the root cause, gives the fix
(`POST /api/v1/pull`, idempotent), states it three separate times (Step 6, the
Step 7 table, the verification checklist), and — best of all — makes it
*diagnosable in advance* by requiring the first inference result be logged
verbatim.

That last move is the difference between documenting a failure and preventing
one.

### 1.3 "Do not call `/api/v1/load` at startup"

Counter-intuitive, correct, and justified rather than asserted: the request body
shape has changed between releases, and a malformed call can destabilise the
server. Pairing it with "loading is the one step you let lemond do lazily —
pulling is not" draws a sharp, memorable line between two things that sound
identical.

### 1.4 The 120-second timeout, with its reason

Making it one of three *mandatory* client changes rather than a tuning note, and
explaining that the common 30s default is shorter than first-run model load — so
the failure presents as a blank UI indistinguishable from a broken integration —
is the right treatment. The per-client table (`httpx.Client(timeout=120)` /
`timeout: 120000` / per-request) means the reader cannot get it wrong through
ambiguity.

### 1.5 Per-stage logging as a first-class requirement

The prescribed log lines:

```
[lemond] Starting on port <port>
[lemond] Healthy on port <port>
[lemond] <recipe>:<backend> installed
[lemond] Pulling model <name>...  →  Model <name> ready
[local]  <modality> result: <value>
```

with "build the logging in from the start — not as an afterthought when
something breaks" and the observation that without it "'nothing happened' is
indistinguishable from 'broke at stage 3'." This is the single most transferable
piece of advice in the skill and it is placed early, where it changes what the
reader builds rather than how they debug.

### 1.6 Release-asset lookup instead of a hand-built URL

Naming the exact trap — the tag carries a leading `v` (`v10.8.0`) but the asset
filename strips it, so a constructed URL 404s — and giving working
PowerShell/bash that queries the GitHub API by stable name pattern is the kind
of detail that quietly saves ten minutes for every single user.

The PowerShell sanity check is a nice touch:

```powershell
if (-not (Test-Path vendor\lemonade\resources\*.json)) { throw "resources/ missing — re-extract and copy again" }
```

### 1.7 The `resources/` warning

> Copying only the binary produces a server that looks healthy but cannot
> function.

Same theme as §1.1 and §1.2 — a failure that passes the obvious check. Correctly
flagged as a full package copy, not a binary copy.

### 1.8 The dev-mode file-watcher caveat

Lemond writes config and cache files at runtime; a watcher (Tauri, Electron,
Next.js, Vite) picks them up, restarts the app, kills the subprocess, and spawns
a new one on a new port — "silently breaking any in-flight transcription." This
is a genuinely non-obvious interaction between two unrelated systems, and it is
the sort of thing only found by hitting it.

### 1.9 Local mode requires no cloud key — treated as a property, not an edge case

> This is a defining property of local mode, not an edge case.

Then enumerated concretely: skip the key-entry screen, short-circuit empty-key
validators to "valid," re-enable the gate only for cloud mode. Step 1 even
pre-stages it by asking the surveyor to record every API-key gate up front. Good
structural thinking — the fix is set up two steps before it is needed.

### 1.10 Honest scope boundaries

Three places where the skill says what it will not do, and means it:

- Runtime hardware fallback on the end user's machine is out of scope; bundle
  Vulkan as the universal fallback.
- "Having an NPU does not mean every recipe supports NPU" — confirm via
  `/api/v1/system-info`.
- System-wide Lemonade is a different problem; go use the installer docs.

### 1.11 `server_models.json` can be stale

"Do not edit or rely on this file … the only authoritative model list is
`GET /api/v1/models` on a running `lemond` instance with the backend already
installed." Exactly right, and the same discipline the sibling `local-ai-use`
skill should adopt for its hardcoded model IDs.

---

## 2. What needs improvement

### 2.1 HIGH — Back-ports are missing, and the client table is wrong for some modalities

Step 5 says every client points at `http://127.0.0.1:{port}/api/v1` and the
per-client table repeats it for all five client types. That is true for chat,
images, TTS, and STT — but not for everything Lemonade serves.

On this box right now, lemond fronts per-slot back-ends on their own ports:

```
:13305  proxy
  :8001  Qwen3-Embedding-0.6B-Q8_0        llamacpp/vulkan   embedding
  :8002  bge-reranker-v2-m3-Q8_0          llamacpp/vulkan   reranking
  :8003  Qwen2.5-VL-7B-Instruct-Q4_K_M    llamacpp/vulkan   llm (+ mmproj)
```

`/v1/rerank` is served from the **back-port**, not from the proxy, and the port
is assigned dynamically — it must be discovered from `GET /api/v1/health`
(`backend_url` per loaded model), not hardcoded.

**Why it matters here more than in the sibling skills:** this skill's whole
premise is that the app's *existing* client gets re-pointed with three changes
and nothing else. An app doing retrieval — embeddings plus rerank, a very common
shape for the local-AI use case this skill targets — will find that rerank 404s
against the documented base URL, with no hint in the skill that a second address
exists. The reader has been told explicitly that three changes suffice.

**Suggested fix.** Add a note under the Step 5 client table:

> **Not every endpoint is on the proxy port.** Chat, embeddings, images, audio,
> and transcription are served from `{port}/api/v1`. Some endpoints — notably
> `/v1/rerank` — are served directly by the per-model back-end on its own
> dynamically assigned port. Read `GET /api/v1/health` and use the `backend_url`
> reported for the loaded model rather than assuming the proxy port.

And add a row to the Step 7 recovery table:

| Symptom | Cause | Recovery |
|---|---|---|
| A modality 404s on `/api/v1` while chat works | Endpoint is served from the model's back-port, not the proxy | `GET /api/v1/health`, read `backend_url` for that model, call it directly |

### 2.1b HIGH — The `@anthropic-ai/sdk` row in the Step 5 table produces a guaranteed 404 (confirmed)

Separate from §2.1 and more clear-cut: this one is a reproducible defect, not a
gap.

The Step 5 client table says:

| Existing client | New `base_url` |
|---|---|
| `@anthropic-ai/sdk` | `http://127.0.0.1:{port}/api/v1` |

The Anthropic SDK appends `/v1/messages` to `base_url`. That configuration
therefore requests `/api/v1/v1/messages`. Probed against live 11.5.2:

```
POST /api/v1/messages     → 404  {"error":{"message":"The requested endpoint does not exist", ...}}
POST /api/v1/v1/messages  → 404  {"error":{"message":"The requested endpoint does not exist", ...}}
POST /v1/messages         → 200  {"content":[{"text":"Hello! How can I assist you today","type":"text"}], ...}
```

(Control: `POST /api/v1/chat/completions` with a real model returns 200, so the
server and the model are fine — it is the path that is wrong.)

**Lemonade does speak Anthropic Messages, but it serves it from `/v1/messages`,
outside the `/api/v1` prefix.** The correct `base_url` for `@anthropic-ai/sdk`
is therefore `http://127.0.0.1:{port}` with no path suffix.

This matters more than a typo because the skill presents `/api/v1` as a uniform
base for every client in the table, and an Anthropic-SDK app following it
verbatim gets a 404 on its very first call — during the exact cold-start window
where the skill has trained the reader to suspect an unpulled model or a short
timeout instead.

**Suggested fix.** Correct the row, and add a note that Lemonade exposes more
than one path prefix:

| Existing client | New `base_url` | Resulting path |
|---|---|---|
| `openai-python` / `openai-node` | `http://127.0.0.1:{port}/api/v1` | `/api/v1/chat/completions` |
| `@anthropic-ai/sdk` | `http://127.0.0.1:{port}` | `/v1/messages` |

> **Path prefixes are not uniform.** OpenAI-compatible routes live under
> `/api/v1`; the Anthropic Messages route is served at `/v1/messages`. Set
> `base_url` to whatever makes the SDK's own path suffix resolve correctly, and
> verify with one real request before wiring up the rest of the app.

Together with §2.1 (back-ports) this is the same underlying theme: the skill
models lemond as one flat namespace on one port, and it is three.

### 2.2 HIGH — The Linux NPU row is questionable **[unverified]**

Step 2's profile table lists:

| App's primary need | Default model | Recipe |
|---|---|---|
| Speech-to-text (Linux NPU) | `whisper-v3-turbo-FLM` | `flm` |

On this box — an XDNA NPU on Linux, the exact target — NPU ASR works, but
**not** as a Lemonade recipe. It runs as a standalone FastFlowLM host process:

```
flm serve qwen3-tk:4b --embed 1 --asr 1     # :52625
```

serving `/v1/chat/completions`, `/v1/embeddings`, and
`/v1/audio/transcriptions` from one process that owns the single AMDXDNA
context. It is managed as a separate slot in my own control plane precisely
because it sits outside Lemonade's accounting.

I have not yet tried `lemonade backends install flm:npu` on Linux, so this is
flagged rather than asserted. But if `flm` is not in fact installable as a
Lemonade backend on Linux, that table row will send readers down a dead end on
the platform where the NPU story is hardest.

Note the skill only shows `flm:npu` in a **Windows** packaging example
(`vendor/lemonade/lemonade backends install flm:npu # Windows NPU path only`),
which slightly contradicts the Linux row above it.

**Suggested fix.** Either confirm and document the Linux `flm` install command
explicitly, or mark the row "Windows only" and add a sentence that Linux NPU ASR
currently runs as a standalone FastFlowLM process outside lemond — which has
real consequences for this skill, since a standalone process is not something
the launcher in Step 4 supervises.

### 2.3 MEDIUM — The one-app-one-server assumption is never stated

The architecture is: each app spawns a private `lemond` on a random port with a
fresh API key. Clean and correct for a single desktop app.

It is not stated what happens when that assumption breaks, and it breaks easily:

- Two apps built with this skill, installed on the same machine → two lemond
  processes, two model caches (or a shared one, depending on `models_dir`), and
  two copies of the same weights competing for one GPU.
- An app built this way running on a machine that *already* has a system-wide
  Lemonade — the case the skill routes away in the "When this skill is the right
  tool" section, but only for the initial choice, not for coexistence.

The `models_dir` guidance ("set to `./models` to keep weights private to the
app") makes the duplication explicit but frames it purely as a privacy choice,
not as a disk-and-VRAM cost. Two apps each bundling a 4B model is ~5 GB
duplicated on disk and two model loads competing for the same GPU.

**Suggested fix.** One short subsection under Step 3's bundle decisions:

> **If more than one app on the machine may do this,** weigh `models_dir: auto`
> (shared HuggingFace cache — deduplicated weights, some coupling between apps)
> against `./models` (private, duplicated). Note that two lemond instances still
> compete for the same GPU regardless of cache choice; there is no cross-process
> arbitration.

### 2.4 MEDIUM — No concurrency or slot model

Related to §2.3 but distinct: even within one app, the skill says nothing about
what happens when two requests arrive at once, or when the app uses more than
one modality.

Lemonade keeps separate slots per model class — embedding, transcription, tts,
reranking, image, llm — and loading into one does **not** evict another. That is
a genuinely useful property for exactly this skill's audience: an app doing
transcribe-then-summarise can keep both models resident. But it also means
memory adds up, and the skill's "pick one default profile, do not ship a buffet"
advice reads as if only one model is ever loaded.

**Suggested fix.** A sentence in Step 2: models of different classes stay
coresident rather than evicting each other, so a multi-modality app should size
memory for the sum, not the max. This turns an unstated risk into a stated
design input.

### 2.5 MEDIUM — Version currency **[unverified]**

The skill's examples reference `v10.8.0`; live here is **11.5.2**. Unverified at
11.x: `POST /api/v1/install` body shape, `POST /api/v1/pull` behavior,
`GET /api/v1/system-info` field names (the skill leans on it for the
recipe/backend `installed` / `installable` probe), and the model IDs in the
Step 2 profile table.

The skill is already appropriately humble about `/api/v1/load` changing shape
between releases — the same caution should extend to the endpoints it *does*
tell you to call.

**Suggested fix.** State a tested-against version range. Given the skill already
instructs the reader to fetch the *latest* release, a note that model IDs and
`system-info` fields should be confirmed against the version actually downloaded
would be consistent with its own `server_models.json` guidance.

### 2.6 LOW — "~30 lines and three changes" may undersell the work **[unverified]**

The opening promises: one ~30-line launcher, three client changes, one vendored
binary. But the body then requires per-stage logging, a loading indicator
covering the whole cold-start sequence, bypassing every API-key gate, a
first-run backend install, a pull step, shutdown handling, and watcher
exclusions.

Those are all justified. But a reader who budgets against the headline will be
surprised, and the verification checklist has **eleven** boxes. The framing
undersells a genuinely medium-sized task, which risks the skill being abandoned
halfway — leaving exactly the half-configured state it warns about.

**Suggested fix.** Keep the headline for the *core* change and add a clause:
"…plus first-run setup (backend install, model pull), progress UI, and
lifecycle handling — budget a day for a first integration." Honest scoping makes
the skill more likely to be finished, not less likely to be started.

### 2.7 LOW — Step 1 numbering

"Record three things before continuing" is followed by a four-item list. The
fourth (API-key gating) is a genuinely important addition — it should be counted.

### 2.8 LOW — Shutdown guidance is inverted from the usual convention

> On app exit, `proc.terminate()` (Unix) or `proc.kill()` (Windows).

On POSIX, `terminate()` sends SIGTERM (graceful) and `kill()` sends SIGKILL
(immediate). On Windows, Python's `subprocess` maps both to `TerminateProcess`,
so they are equivalent there. Written as an OS split, it reads as though Windows
requires the harsher call, when in fact the distinction is that Windows has no
graceful equivalent.

Combined with "lemond flushes config and exits cleanly within a couple of
seconds," the guidance should probably be: `terminate()` everywhere, then
`wait(timeout=…)`, then `kill()` as a fallback if it has not exited.

**Suggested fix.** Rewrite as: terminate, wait with a timeout, escalate to kill —
and note that on Windows the two are the same call, so the wait is what actually
matters.

---

## 3. Applicability finding

### 3.1 HIGH — Step 1's survey patterns miss a real cloud-AI client

> **Revised 2026-08-11.** An earlier draft claimed the skill's precondition was
> unmet across every repo I checked, based on a grep using the skill's own Step
> 1 patterns. That conclusion was wrong — and *why* it was wrong turns out to be
> a finding about Step 1.

Step 1 tells the surveyor to search for:

```
openai, OpenAI(, chat.completions, responses.create
anthropic, Anthropic(, messages.create
api.openai.com, api.anthropic.com, localhost:11434
OPENAI_API_KEY, ANTHROPIC_API_KEY
```

Running exactly that across `instinct-dash`, `multitool`, `strix-halo-bench`,
and `octant-private` returns **zero source hits**. I initially reported that as
"no host application exists here."

It is wrong. `strix-halo-bench/scripts/common/judge.py` is a first-class cloud
AI client:

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
2023-06-01` headers. It is squarely the shape this skill targets. Every Step 1
pattern misses it because it uses **raw HTTP with project-specific env var
names** (`JUDGE_API_KEY`, `JUDGE_BASE_URL`) rather than a vendor SDK.

The same is true more broadly: my litellm deployment and daily workflow use
commercial models constantly. The addressable audience is *not* narrow — my grep
was.

**Why this is a defect in the skill, not just my mistake.** Step 1 is the step
that decides whether the skill applies at all. An agent that runs those patterns,
gets nothing, and concludes "this app has no cloud AI to replace" will decline a
job it should have taken. Vendor-SDK imports are the easy case; hand-rolled HTTP
clients with local naming conventions are common in exactly the
research/benchmark/internal-tooling code most likely to want a local backend.

**Suggested fix.** Add a second, behavioural tier to the Step 1 search:

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
> through one config point, it may in fact be *easier* to re-point than an
> SDK-based app.

### 3.1b `judge.py` is a strong candidate host, and better than my earlier suggestion

Worth recording because it changes the test plan. `judge.py` satisfies Step 1's
hardest requirement out of the box:

> **One single place** where the base URL and API key are constructed. If there
> isn't one, refactor to one before going further.

It already has that — `_resolve_backend()` returns an `(kind, model, endpoint,
headers)` tuple, and the backend is chosen by a selector string. It even already
has a `local:` option pointing at a local CCR. Adding a `lemonade:` selector is
close to the minimal possible version of this integration, which makes it a good
control: if the skill's "three changes" claim is going to hold anywhere, it
holds here.

It also exercises §2.1b directly, since the judge speaks Anthropic Messages —
the exact client whose `base_url` row is wrong.

Caveat on framing: `judge.py` is a batch harness, not a desktop app, so it will
not exercise the progress-UI or key-gating requirements. Using "Claude as a
judge" there was a deliberate design decision rather than a constraint, so a
local judge backend is a legitimate thing to want, not a contrivance.

### 3.2 The gap: one server, many networked consumers

Between the two skills:

- `local-ai-use` → one workspace, one agent, system-wide server.
- `local-ai-app-integration` → one app, one private embedded server.

Neither covers: **one Lemonade instance, many consumers over a network.** That
is my actual topology and I suspect it is common for anyone with a homelab or a
team box — a GPU machine serving several apps, agents, and containers over
Tailscale/Consul.

Evidence it is an unserved gap: my homelab repo has litellm, claude-code-router,
open-webui, and embedchain all deployed — all of them routinely calling
commercial models — and `grep -rilE 'lemonade|13305|strix' terraform/` returns
**zero hits**. The fleet has no on-ramp to the local Lemonade box, and neither
skill provides one. This skill explicitly routes that user to a docs link and
stops.

Note this sharpens §3.1 rather than contradicting it: there is plenty of
commercial-model traffic to redirect here. What is missing is not demand or
candidate applications — it is a skill for the topology those applications
actually run in.

The missing content is real and specific: binding beyond loopback, `LEMONADE_API_KEY`
as a shared secret rather than a per-launch random, service discovery, back-port
exposure (§2.1), and concurrency across consumers (§2.4). That is arguably a
fourth skill.

---

## 4. Planned live testing

`instinct-dash` is the only viable in-tree host, and only after adding a feature
that needs an LLM. It is a good instrument for three of the skill's specific
claims: it is a Vite app (§1.8's watcher hazard), it uses `openai-node`'s client
shape, and it has a Playwright harness with `@mocked` / `@api` / `@live` tags to
gate the result.

| # | Test | Effort | Settles |
|---|---|---|---|
| T0 | **Add a `lemonade:` backend selector to `strix-halo-bench/scripts/common/judge.py`** — the minimal real integration, and the natural control for the "three changes" claim | ~2 hrs | §2.1b, §2.6, §1.4 |
| T1 | Endpoint smoke against live 11.5.2: `/api/v1/pull`, `/api/v1/install`, `/api/v1/system-info` field names, `lemonade backends install` | ~45 min | §2.5 |
| T2 | `lemonade backends install flm:npu` on Linux — does the Step 2 Linux NPU row work at all? | ~30 min | §2.2 |
| T3 | Full integration into `instinct-dash` ("summarise this GPU telemetry locally"): vendor the package, reference launcher, three client changes, pull step | ~half day | §2.6, §1.4, general |
| T4 | Deliberately skip the pull step and confirm the empty-200 failure reproduces at 11.5.2 | ~15 min | §1.2 |
| T5 | Run T3 under `npm run dev:ui` **without** excluding `vendor/` from the Vite watcher, and confirm the restart/orphan hazard | ~20 min | §1.8 |
| T6 | Rerank against the documented base URL, confirm it 404s, confirm `backend_url` from `/api/v1/health` works | ~20 min | §2.1 |

T0 is new and now leads: `judge.py` is a better first host than `instinct-dash`
because it is a real existing cloud client with the single-config-point
precondition already satisfied, and it speaks the wire format whose `base_url`
row is wrong (§2.1b). It also produces something independently useful — an
offline judge path for benchmark reruns.

T4 and T5 are deliberately *reproduction* tests of the skill's own warnings —
confirming a documented hazard is real at 11.5.2 is as useful as finding a new
one, and much cheaper.

---

## 5. Summary

The best-written of the three. Its organising insight — that this integration
fails silently at five distinct stages, so the job is instrumenting each
transition — is correct, and it is applied consistently rather than stated once.
The empty-200 diagnosis, the mandatory 120s timeout with its reason, the
`resources/` warning, and the file-watcher hazard are all things a reader could
not derive from the API docs.

The substantive gaps share one root cause: the skill models lemond as a single
flat namespace on a single port serving a single app. In fact it is three
namespaces (`/api/v1`, `/v1`, and per-model back-ports) on multiple ports. From
that follow the confirmed `@anthropic-ai/sdk` 404 (§2.1b), the missing
back-ports and the consequently wrong `/v1/rerank` guidance (§2.1), and the
absent model of coresidency and concurrency (§2.3, §2.4). The Linux NPU row also
needs verification (§2.2).

Step 1's survey patterns are the other actionable defect: they find vendor SDKs
but miss hand-rolled HTTP clients, which caused me to wrongly conclude the skill
had no candidate host here when in fact a good one was sitting in
`strix-halo-bench` (§3.1). That is the failure mode most likely to make an agent
decline a job it should take.

Separately and more strategically: the topology I actually run — one server,
many networked consumers, plenty of commercial traffic to redirect — is served
by neither this skill nor `local-ai-use` (§3.2). Worth a conversation about
catalog coverage independent of any edit here.
