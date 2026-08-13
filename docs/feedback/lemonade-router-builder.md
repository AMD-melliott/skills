# Feedback — `lemonade-router-builder`

**Reviewer:** Matt Elliott
**Reviewed at:** `amd/skills` @ `cf5e518`
**Hardware:** AMD Strix Halo (gfx1151), 128 GB unified memory, XDNA NPU, Pop!_OS 24.04
**Lemonade:** `lemonade-server 11.5.2~24.04` (PPA), system `lemond.service`, `:13305` healthy

Review of `SKILL.md`, `reference.md`, `examples.md`, and `scripts/validate.py`
against a live 11.5.2 server and a production local-inference stack. Everything
below is confirmed against the running server unless stated otherwise; §4
records what was measured and what was deliberately not run.

**This document holds design feedback, open questions, and measurement results
only.** Mechanical corrections were submitted separately as a pull request:

| PR | Covers |
|---|---|
| `docs(lemonade-router-builder): clarify Mode A trace reading and example scope` | `default_used` as the fallback signal, added to Step 8 (the minimal half of §2.2); the Mode A trace shape — synthetic `__route_N` ids, empty-`rationale`-on-success, the three-field fallback signature (§2.3); `examples.md` are shape references, not runnable policies (§2.4) |

---

## Reviewer context

Relevant because it shapes what I noticed and what I missed. This box runs a
multi-slot Lemonade stack in daily use:

```
:13305  proxy
  :8001  Qwen3-Embedding-0.6B-Q8_0     llamacpp/vulkan   embedding:1
  :8002  bge-reranker-v2-m3-Q8_0       llamacpp/vulkan   reranking:1
  :8003  Qwen2.5-VL-7B-Instruct-Q4_K_M llamacpp/vulkan   llm:1 (+ mmproj)
```

It also already runs **three** other routing layers, which is the lens I read
this skill through:

| Layer | Routes on |
|---|---|
| `claude-code-router` `Router` block | request class (default / background / think / longContext + token threshold) |
| litellm (Nomad) | model name → provider |
| `mtctl resolve` (own control plane) | model registry + GPU-arbiter state + slot readiness |
| **`collection.router`** | **prompt content** — keywords, regex, length, images, tools, metadata, classifiers |

`collection.router` is the only content-aware layer of the four. That is a real
differentiator and the skill should lean into it harder than it currently does.

---

## 1. What works well

### 1.1 The mode fork is the right first decision, and it is enforced

Making "LLM-as-router vs. rules" the *first* thing the skill decides — with a
concrete trigger ("the user names any concrete signal") rather than a vibe — is
good design. Better still, the skill enforces mutual exclusivity three separate
times (the table note, Step 4's all-caps warning, and the defaults summary). For
a schema violation the server rejects outright, that redundancy is earned rather
than padding.

### 1.2 The prompt-authoring guidance is the most valuable content here

Step 4's explanation that the engine **unconditionally appends its own JSON
reply contract** — and that authoring "reply with ONLY the model name" therefore
causes weaker judges to emit a bare string, fail the parse, and silently fall
back to `default_model` — is exactly the kind of thing that costs a user a day
and cannot be discovered by reading the schema. The good/bad prompt pair makes
it concrete, and the explicit banned-verb list ("pick", "output", "reply with",
"respond with") makes it checkable.

The same reasoning is correctly repeated for `type: "llm"` classifiers in Step 5
rather than left as an exercise. Good.

### 1.3 Scope discipline

"Generates and validates the JSON only — does not register it or call the live
server" is stated in the frontmatter, restated in the opening paragraph, and
enforced in Step 8b ("Do not execute these with Bash or any tool — print them as
text only"). A skill that knows what it is *not* is rarer than it should be.
This also keeps it testable offline, which is why §4's T1 costs 30 minutes
instead of a day.

### 1.4 The offline validator as a hard gate

`scripts/validate.py` (512 lines, stdlib-only) plus "do not present a policy that
fails this check" converts the deterministic part of the task into a script
instead of trusting the model. This matches CONTRIBUTING's "lean on scripts for
the deterministic parts" and is the single biggest reliability lever in the
skill.

### 1.5 Small footguns named explicitly

Several of these are the sort of thing only someone who has been bitten
documents:

- `/pull` is idempotent per `model_name`, so a second policy under the same name
  silently overwrites the first — hence the derived-name guidance and the
  "don't reuse a name from earlier in this conversation" rule.
- `keywords_any` is case-insensitive **substring**, so `"hi"` matches inside
  `"shipping"`. The pointer to `regex` with `\b…\b` is the right fix.
- Rule order is first-match-wins, with the privacy-before-topic example
  ("a 'sensitive stays local' rule must precede a 'code goes to the big model'
  rule, or coding prompts with PII leak"). Naming the failure, not just the
  rule, is what makes it stick.
- `semantic_similarity` rejects a `labels` key because concept names *are* the
  labels — a non-obvious asymmetry with the other two classifier types.

### 1.6 Defaults table

The Step-by-step body and the defaults summary agree with each other, and the
table gives the agent a single place to resolve "user didn't say." This is the
part of the skill most likely to keep two runs consistent.

---

## 2. What needs improvement

Ordered by impact.

### 2.1 HIGH — Nothing about slot contention or load latency

This is the biggest gap, and it is the first thing a real multi-slot user hits.

A policy names N candidates. A Lemonade host has a bounded number of slots — on
this box, one `llm:1` occupied by a 7B vision model, with embed and rerank
coresident. The skill never says what happens when the router picks a candidate
that is not currently loaded:

- Does lemond auto-load it?
- Does it evict the current `llm:1` occupant?
- What is the added latency on the routed request — and does the router's own
  judge call (Mode A) contend for the same slot as the candidate it selects?
- Can a two-candidate policy thrash the slot on alternating requests?

**Why it matters beyond this box:** a user who authors a perfectly valid
three-candidate policy on a laptop will see p99 latency that looks like a bug.
The skill's whole value proposition is "the JSON is accepted on the first try" —
but accepted-and-valid is not the same as *operationally sane*, and right now
the skill implies the former guarantees the latter.

**Measured at 11.5.2.** Directly requesting three LLM-class models in sequence
evicts each time — `/api/v1/health` reports **1** resident after each, with
load+infer of 3.6 s (tiny), 6.3 s (E4B), 7.0 s (9B). But a *router* policy holds
**two** LLM-class models: alternating its two candidates over six requests gave
constant ~3.7 s latency with no reload penalty and 2 resident throughout, on
separate back-ports. Cold route with everything unloaded was 2.90 s against
0.69 s warm.

So a Mode A policy needs room for **judge + candidate**, not one model — and on
a host where candidates cannot be coresident, every alternation pays a load. On
this 124 GiB host the effect was invisible; on a laptop it would not be.

**Suggested fix.** Add a short "Step 3a — candidates and slots" note, and one
row to the defaults table:

> **Candidates share the host's model slots.** Every candidate the router may
> pick has to be loadable in the LLM slot. If two candidates cannot be resident
> at once, alternating traffic will pay a model-load cost on each switch. Prefer
> 2–3 candidates that are either coresident or cheap to swap, and put the
> highest-traffic one in `default_model`. In Mode A, the `router.model` judge
> also occupies a slot — making it one of the candidates avoids a third
> resident model.
>
> `GET /api/v1/health` lists what is currently loaded.

That last sentence is worth adding regardless: it is how the rest of the stack
does discovery and it is not mentioned anywhere in the skill.

### 2.2 HIGH — `route_trace` is under-sold and arrives too late

The `x-lemonade-route` header and the `"route_trace": true` body field are the
only way to tell a working policy from one that is silently falling back — which
is the exact failure the skill spends most of Step 4 warning about. Yet they
appear in a two-sentence paragraph *after* the curl block at the very end of
Step 8.

Right now the skill tells the user "here is a catastrophic silent failure mode"
and then buries the instrument that detects it.

**Suggested fix.** Promote it to its own Step 9, "Verify the policy actually
routes," with an explicit acceptance test:

```bash
# Send one prompt per rule (plus one that should hit no rule) and confirm
# matched_rule is what you expect — not `default` for everything.
curl -sS -X POST http://localhost:13305/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"<model_name>","route_trace":true,
       "messages":[{"role":"user","content":"<prompt targeting rule-N>"}]}' \
| python3 -c 'import json,sys; d=json.load(sys.stdin)["x_lemonade_route"]; print(d["matched_rule"], d["default_used"])'
```

> **If `default_used` is true for every prompt, the policy is not routing.** In
> Mode A this almost always means the judge's reply failed to parse — re-read
> the prompt rules in Step 4.

That connects the warning to its diagnostic, which is currently the missing link.

*Partially addressed in the PR* — Step 8 now says to read `default_used`. That
is the one-paragraph version. The structural change (a named verification step
with a per-rule acceptance loop) is a design decision and is left here.

### 2.3 HIGH — The silent-fallback hazard is real, but the prescribed fix does not prevent it (measured)

Step 4 makes a strong, falsifiable claim: an *imperative* router prompt
("Pick X…", "Reply with ONLY the model name") makes weaker judges emit a bare
string, fail the engine's JSON parse, and fall back to `default_model` **on
every request with no visible error** — and that writing *intent-only* prompts
prevents this.

I measured it. Four Mode A policies, identical but for two variables — prompt
style and judge model — over the same 24 prompts (12 with obvious PII, 12
plainly generic). Candidates `Gemma-3-4b-it-GGUF` and `Tiny-Test-Model-GGUF`.
96 routed requests at 11.5.2:

| judge | prompt style | n | default_used | accuracy |
|---|---|---|---|---|
| `Gemma-3-4b-it-GGUF` | imperative | 24 | **0 (0%)** | 23/24 (96%) |
| `Gemma-3-4b-it-GGUF` | intent-only | 24 | **0 (0%)** | 24/24 (100%) |
| `Tiny-Test-Model-GGUF` | imperative | 24 | **24 (100%)** | 12/24 (50%) |
| `Tiny-Test-Model-GGUF` | intent-only | 24 | **24 (100%)** | 12/24 (50%) |

(50% accuracy under fallback is an artefact — always serving `default_model`
scores the 12 generic prompts correct by accident.)

**The warning is vindicated.** With a weak judge, 100% of requests fell back,
and the failure is exactly as quiet as the skill says:

```json
{ "header": "default", "route_to": "Tiny-Test-Model-GGUF",
  "default_used": true, "matched_rule": "", "rationale": "", "score": 0.0 }
```

HTTP 200, no error field. Invisible without `route_trace` — which is precisely
why §2.2 argues that instrument deserves promotion.

**The remedy is refuted.** The intent-only prompt the skill prescribes fell back
**100% of the time** with a weak judge, identically to the imperative prompt it
warns against. With a capable 4B judge, *both* styles worked and neither ever
fell back. The determinant is **judge capability, not phrasing**.

**And the skill's own default is the failure mode.** Step 4 says `router.model`
"defaults to the smallest candidate." Here the smallest candidate as judge
produced 100% silent fallback *while following the prompt guidance exactly*. A
user who takes both defaults gets the documented catastrophe.

**Suggested changes.**

- **Keep** the failure description and the emphasis on `route_trace`.
- **Replace** prompt style as the primary control with **judge selection**: the
  judge must reliably emit strict JSON; verify with `route_trace` before
  shipping; a model too small to hold the format falls back on every request no
  matter how the prompt is worded.
- **Change the `router.model` default.** "Smallest candidate" is the riskiest
  available choice. Note the tension with memory (§2.1): the smallest judge
  minimises resident footprint, which is a genuine benefit — so state the
  trade-off rather than presenting it as free.
- **Demote the banned-verb list** ("pick", "output", "reply with") to a style
  preference. Measured effect was 24/24 vs 23/24 with a capable judge — within
  noise, and the single miss was a judgement call (`matched_rule: __route_1`, a
  valid decision), not a parse failure.

*Caveat:* `Tiny-Test-Model-GGUF` is a deliberate floor — a test fixture weaker
than anything realistically deployed. It establishes that capability is the
boundary, not where the boundary sits. A ladder of judge sizes would locate the
threshold; not run.

*The trace-reading gotchas this experiment surfaced* — synthetic `__route_N`
ids, empty-rationale-on-success, and the unambiguous fallback signature — are
factual and went into the PR. The argument above about **judge selection versus
prompt phrasing**, and the `router.model` default, are design calls and stay
here.

### 2.4 RESOLVED — Version currency is fine at 11.5.2 (tested)

The skill requires "v10.1.0+". Live here is **11.5.2**. The prerequisites and
the parser-strictness claims in `reference.md` have presumably not been
re-checked against 11.x.

**Tested, and the news is good.** I compared the offline validator against the
live parser on 13 policies — one valid baseline plus 12 mutations, each
targeting a different documented rule. **13/13 agreement, zero disagreements in
either direction**, and in particular **no false negatives** (validator says
ready, server rejects), which is the class that would actually hurt a user.

Mutations rejected by both: Mode A + Mode B together; `default_model` not in
candidates; `route_to` not a candidate; `semantic_similarity` declaring
`labels`; `llm` classifier without `labels`; `min_score: 1.5`; `min_chars: -10`;
`default_label` not in labels; a model referenced but absent from `components`;
a rule referencing an undeclared classifier id; `version: 1` as an int; and
`model_name` without the `user.` prefix.

All 7 shipped `examples.md` policies pass offline with zero errors and zero
warnings, and a hand-authored Mode B policy using only locally-downloaded models
(with both a `classifier` and a `semantic_similarity` classifier) passes offline
and registers live.

**Remaining suggestion is small:** state the tested-against range in the
prerequisites so a future reader knows when the claim was last checked. The
parser contract the validator mirrors is intact two minor versions on, which is
worth saying out loud.

**One note for `examples.md`** (in the PR). Several shipped examples reference
models a given host will not have, so they validate offline but fail live with
`400 Collection component not registered: '<model>'`. That is correct,
documented behaviour — the validator's docstring is explicit that model
existence needs a live server — but nothing said so where a reader would look.

### 2.5 MEDIUM — No guidance on composing with an external control plane

The skill implicitly assumes `collection.router` is the whole routing story. In
practice it is usually one layer among several — here it would sit under CCR and
alongside a registry-bound resolver.

Unanswered, and reasonable for a user to ask:

- Should content-based routing live in `collection.router` or in the caller?
- If a caller already picks a model, does a router policy override it?
- Is it sane to have a router policy as a *candidate* of another router policy?

**Suggested fix.** A short "Where this fits" section near the top — three or four
sentences distinguishing `collection.router` (content-aware, server-side,
per-request) from client-side routers (request-class-aware, no prompt
inspection). This also strengthens the skill's pitch: content-awareness is the
thing the other layers structurally cannot do.

### 2.6 HIGH — Nothing validates `labels` against the classifier model's real output (measured)

A Mode B policy routinely spans two runtimes: candidates and
`semantic_similarity` models are `llamacpp`, while a `classifier` model is an
`onnxruntime` encoder. I set out to test a narrower, inferred version of this
finding — that an uninstalled `onnxruntime` backend would fail to load and
silently misroute via `on_error: "match_false"`. That mechanism **did not
reproduce**, but the experiment surfaced a different, measured hazard with the
same silent-misroute signature.

**Backend-absent is not a hazard at 11.5.2.** `onnxruntime:cpu` was
`installable` (not installed) on this host. I registered a Mode B policy with
a `classifier` leaf on `Bert-Phishing-ONNX` and routed real traffic through it.
`journalctl` shows lemond installing `ort-server` on first use, transparently,
the same way it fetches an undownloaded checkpoint — the classifier loaded and
ran. A working chat path *does* generalize to a classifier's runtime here,
which is the opposite of what I expected to find.

**What actually causes silent misrouting: `labels` is never checked against
the model.** My first policy declared the classifier label-less, per
`reference.md`'s "legal for single-score models" rule. `Bert-Phishing-ONNX` is
not single-score — its `id2label` is `{0: "benign", 1: "phishing"}` — so every
request scored `0.0` and fell through, with `route_trace` showing
`default_used: true` and no hint why. Re-registering with the correct
`"labels": ["benign", "phishing"]` fixed it: the same phishing prompt then
scored `0.9999949` and routed correctly.

To isolate the mechanism, I then registered a third variant with **fabricated
labels** — `"labels": ["spam", "ham"]`, names that don't exist on the model —
and routed the identical 99.9997%-confidence phishing prompt through it. Both
`scripts/validate.py` and the live `/api/v1/pull` accepted the policy without
complaint. The request came back `default_used: true, matched_rule: "",
score: 0.0` — HTTP 200, and `journalctl -u lemond` shows no warning, error, or
mention of the mismatch anywhere in the stack.

So the failure isn't `on_error` at all — no error occurs. A `classifier` leaf
whose `label` doesn't exist on the model (wrong name, typo, or a label-less
declaration against a model that isn't single-score) reads back an
unconditional `0.0` by design, and nothing in the validator, the live parser,
or the server logs distinguishes that from a working rule that simply didn't
match this request.

**Suggested fix.** `scripts/validate.py` cannot check this offline — it has no
way to know a classifier model's real output labels — but the *registration*
step could: the server already loads the model to check capability, so
`/api/v1/pull` cross-checking declared `labels` against the model's real
label set (and rejecting a label-less declaration against a model that isn't
single-score) would turn this into the same loud, first-try rejection the
parser already gives for a `route_to` that isn't a candidate. Short of that,
one sentence in Step 5: verify a classifier's `labels` against the model's
`id2label`/card before shipping, and confirm with `route_trace` that a rule
you expect to fire actually does — because neither validate.py nor the live
parser will catch a wrong label name.

*Full transcript, including the backend-absent test and the auto-install log
lines:* `skills/.local/docs/p3-onnx-classifier-test.md` (not checked in —
gitignored scratch).

### 2.7 LOW — Step 8's mandatory-pairing language fights the checklist

Step 8 opens with "These two actions are a single mandatory step. Do not stop
between them," then labels them 8a and 8b. If they truly cannot be separated,
they should not be numbered separately; if the concern is the agent halting
after validation, say that directly.

Minor, but this skill is otherwise unusually precise about instruction shape, so
it stands out.

### 2.8 LOW — `metadata` caveat is buried in a table cell

"not editable in the desktop UI yet — use only when the user asks for metadata
routing" is a meaningful constraint sitting in the last cell of the match-leaf
table. A user who picks `metadata` routing and then cannot see it in the Hybrid
Router editor will assume the policy is broken.

**Suggested fix.** Keep the table row, and add a sentence under the table listing
which match types round-trip through the desktop editor and which do not.

### 2.9 LOW — `min_score` semantics could use one example

`{"classifier": "clf-1", "label": "PII", "min_score": 0.5}` is described as a
"band test" with `min_score`/`max_score` in `[0,1]`. It is not stated whether
the bound is inclusive, nor what a sensible threshold looks like for the
`semantic_similarity` type specifically (cosine similarity scores cluster very
differently from a classifier's softmax output — 0.5 is a reasonable default for
one and quite aggressive for the other).

**Suggested fix.** One sentence in `reference.md` on typical score ranges per
classifier type.

---

## 3. Suggestions worth considering

Not defects — ideas that would raise the ceiling.

### 3.1 Ship a `--dry-run` route simulator

The validator proves the JSON parses. It cannot tell the author that `rule-3` is
unreachable because `rule-1` subsumes it — the single most likely *semantic*
error given first-match-wins plus substring matching.

**Prototyped — cheap, and it catches exactly that case.** ~110 lines reusing
`validate.py`'s existing match-expression grammar: walk `routing.rules`
first-match-wins per prompt, evaluate `keywords_*` / `regex` / `min_chars` /
`max_chars` deterministically, and raise "requires server" for any
`classifier`/`has_tools`/`has_images` leaf reached before a match — reporting
the rule as indeterminate for that prompt rather than guessing.

Against a 3-rule policy (`rule-1` on `"code"`, `rule-3` on `"code review"`,
both text `keywords_any`), four prompts including one containing "code
review", the prototype flags exactly the predicted shadowing:

```
Never hit by any prompt in this set: ['rule-3-code-review']
rule-1-code       <- 'Can you review this code review checklist for me?'
rule-1-code       <- 'please help me write some code for a script'
rule-2-shipping   <- 'track my shipping order status'
default (...)     <- "what's the weather today"
```

Against a mixed policy (one keyword rule, one `classifier` rule), the same
four prompts all report `REQUIRES SERVER (classifier 'phish-clf'...)` once the
keyword rule fails to match — the intended fallback for the case the offline
tool structurally cannot resolve, rather than a false claim either way.

No server call in either run. This is worth shipping — the grammar walk
already exists in `validate.py`; a `--simulate prompts.txt` flag is additive to
the same file. Prototype: `skills/.local/scripts/router_simulate.py` (not
checked in — gitignored scratch; a real submission would fold this into
`validate.py` rather than ship a second script).

### 3.2 Emit a starter prompt set alongside the policy

Step 8b asks for "a short `<test prompt>` that should hit the first rule." Going
one better — one prompt per rule plus one that should reach `default_model`,
written to `router-prompts.txt` — turns §2.2's verification step into a loop the
user can actually run, and pairs naturally with 3.1.

### 3.3 Warn on classifier-only policies with no deterministic fast path

A policy whose every rule depends on a `classifier` or `llm` leaf adds an
inference call to *every* request. That is a real cost that the current defaults
do not surface. A validator warning — "no rule can be decided without a model
call; consider a keyword or length fast path for the common case" — would be
cheap and useful.

### 3.4 Say something about the empty-candidate-set failure

"If the user names none, ask — never invent model names" is right. Consider also
covering the adjacent case: the user names a model that is not in the local
registry. `curl /api/v1/models/<id>` is already curl #1 in Step 8b, but nothing
says what to do when it 404s — pull it, substitute, or stop and ask.

### 3.5 Publish the policy contract in a machine-readable form

`scripts/validate.py` is a hand-written mirror of the server's parser, and §2.4
shows the mirror is exact today. Nothing keeps it that way, because there is no
machine-readable contract to check it against: at 11.5.2 the server serves no
fetchable spec of any kind — `/openapi.json`, `/api/v1/openapi.json`,
`/swagger.json`, `/api/openapi.json` and `/v1/openapi.json` all 404, while
`/docs`, `/redoc` and `/openapi` return the SPA shell. Confirming the validator
still matches a new release therefore means re-running T1 by hand.

A JSON Schema for `collection.router` shipped next to the parser — or a
server-side validate/dry-run endpoint that accepts a policy without registering
it — would let `validate.py` be generated or diffed in CI rather than
re-measured. The same schema would settle §2.9's score-range question in the
place a reader already looks.

### 3.6 Question: this skill is not published, and nothing flags that

Not a defect, and not something I would patch — a publication decision is AMD's
to make. But it is invisible from inside the repo, so it is worth surfacing.

At `cf5e518` there are **7 skills on disk and 4 in the marketplace**.
`lemonade-router-builder`, `magpie-kernel-evaluator`, and
`serving-llms-on-epyc` are absent from the `skills` array in
`.claude-plugin/marketplace.json`. `lemonade-router-builder` additionally
appears in **neither** derived manifest.

`./.github/scripts/check.sh` passes anyway: `validate_skills.py` validates every
skill directory it finds, and the two `--check` generators only assert that the
derived manifests match the hand-maintained source array — so a skill omitted
from that array is consistently omitted everywhere and nothing reports it.

Two readings, and I cannot tell which applies:

- **Deliberate** — these are staged, incubating, or federated elsewhere. Then a
  one-line note in `CONTRIBUTING.md` about what gating publication means would
  save the next reviewer the same detour.
- **Accidental** — a skill was added and the array was not updated. Then a
  `validate_skills.py` warning (not error) of the form
  `skill 'X' is not listed in marketplace.json` would catch it for free, and
  would have caught it here.

Either way, a contributor who follows Path A in `CONTRIBUTING.md` today gets a
green `check.sh` on a skill that no user will ever install.

---

## 4. Testing performed

| # | Test | Status | Settles |
|---|---|---|---|
| T1 | Validator vs live parser — 13 policies (1 valid + 12 targeted mutations) | **done**; 13/13 agreement, no false negatives | §2.4 |
| T2 | Silent-fallback experiment — 4 Mode A policies × 24 prompts = 96 routed requests, varying prompt style and judge model | **done**; warning vindicated, remedy refuted | §2.3 |
| T3 | Slot behaviour — direct sequential loads vs. a 2-candidate router alternating over 6 requests | **done**; direct loads evict, router candidates stay coresident on separate back-ports | §2.1 |
| T4 | `semantic_similarity` accuracy against a ground-truth corpus with known terminology drift | **not run** | §2.9, §3.3 |
| T5 | Mode B `onnxruntime` classifier — backend-absent registration, label-less vs. correct vs. fabricated `labels`, live routing | **done**; backend-absent hazard refuted (auto-installs), unvalidated-`labels` hazard confirmed | §2.6 |

**T4 was dropped deliberately.** It would measure the *classifier model's*
retrieval quality, not the skill's behaviour — a different model would give a
different number and neither would say anything about whether the generated JSON
is correct. §2.9 asks for one sentence on typical score ranges per classifier
type; that is an authoring note AMD can write from its own model cards more
cheaply and more accurately than I can infer it from one corpus.

**`evals/evals.py` was not run.** It needs the `claude` CLI behavioural harness
with an LLM judge, and it grades agent behaviour rather than the artifact. The
parser-agreement matrix (T1) is the higher-value deterministic check and it
came back clean.

Nothing further is planned. The claims worth testing — that the offline
validator matches the live parser, that the silent-fallback hazard is real,
that a multi-candidate policy behaves on a bounded-slot host, and that a
Mode B classifier leaf can silently misroute — are all settled.

---

## 5. Summary

Genuinely well built. The scope discipline, the offline validator gate, and
especially the prompt-authoring guidance derived from the engine's appended
contract put this above most config-generator skills — it teaches the reader
things the schema cannot.

The gap is that it treats the policy as a **document** rather than as something
that runs on a **host with finite resources**. Everything in §2.1 and §2.2 comes
from that: no slot model, and the verification instrument for its own headline
failure mode arriving last and under-emphasised. Both are additive fixes; none
requires restructuring.

Two measured results contradict the skill, both silent-misroute, both from
causes it doesn't name. In Mode A, the prescribed remedy for silent fallback
is prompt phrasing, and phrasing turned out not to be the determinant — judge
capability is (§2.3), and the skill's own `router.model` default is the
failing configuration. In Mode B, I set out to test a backend-loadability
hypothesis and it didn't hold — but the same experiment showed neither
`scripts/validate.py` nor the live parser checks a `classifier` leaf's
`labels` against what the model actually outputs, so a wrong label name
silently and permanently never matches (§2.6). Judge selection in Step 4 is
the single change I would make first; label validation at registration is the
second.

Separately, this skill is not in the marketplace manifest and `check.sh` does
not notice (§3.6) — a question for AMD rather than a patch.
